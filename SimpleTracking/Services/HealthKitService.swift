import Foundation
import HealthKit
import CoreLocation

@Observable
final class HealthKitService {
    static let shared = HealthKitService()

    private let store = HKHealthStore()

    var isAuthorized   = false
    var todaySteps     = 0
    var todayCalories  = 0.0
    var todayDistanceKm = 0.0
    var workouts: [WorkoutRecord] = []
    var isLoading      = false

    // Import progress (used by the "Health-Daten importieren" button in Settings).
    var importInProgress = false
    var importProgress: Double = 0      // 0…1
    var importStatus: String = ""
    var importedCount: Int = 0
    var importedRouteCount: Int = 0
    /// Per-source breakdown from the last import. Shown in Settings so the
    /// user can immediately spot missing sources (e.g. Garmin Connect = 0).
    var importSourceBreakdown: [(name: String, count: Int)] = []

    // Profile characteristics read from Apple Health (fallbacks to UserSettings if absent)
    var hkBiologicalSex: HKBiologicalSex = .notSet
    var hkDateOfBirth:   DateComponents? = nil
    var hkLatestWeightKg: Double = 0
    var hkLatestHeightCm: Double = 0

    private let readTypes: Set<HKObjectType> = [
        HKObjectType.quantityType(forIdentifier: .stepCount)!,
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
        HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
        HKObjectType.quantityType(forIdentifier: .distanceCycling)!,
        HKObjectType.quantityType(forIdentifier: .heartRate)!,
        HKObjectType.quantityType(forIdentifier: .bodyMass)!,
        HKObjectType.quantityType(forIdentifier: .height)!,
        HKCharacteristicType(.biologicalSex),
        HKCharacteristicType(.dateOfBirth),
        HKObjectType.workoutType(),
        HKSeriesType.workoutRoute(),
    ]

    private let writeTypes: Set<HKSampleType> = [
        HKObjectType.quantityType(forIdentifier: .stepCount)!,
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
        HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
        HKObjectType.quantityType(forIdentifier: .distanceCycling)!,
        // Nutrition — written from FoodLog
        HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)!,
        HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates)!,
        HKObjectType.quantityType(forIdentifier: .dietaryWater)!,
        // Body metrics — synced from settings fallback values
        HKObjectType.quantityType(forIdentifier: .bodyMass)!,
        HKObjectType.quantityType(forIdentifier: .height)!,
        HKObjectType.workoutType(),
        HKSeriesType.workoutRoute(),   // required for HKWorkoutRouteBuilder
    ]

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
        isAuthorized = true
        await refreshProfile()
        await refreshTodayData()
        await loadWorkouts()
    }

    // MARK: - Profile (biological sex, date of birth, weight)

    func refreshProfile() async {
        let sex   = (try? store.biologicalSex().biologicalSex) ?? .notSet
        let dob   = try? store.dateOfBirthComponents()
        let mass  = await fetchLatestBodyMassKg()
        let height = await fetchLatestHeightCm()
        await MainActor.run {
            hkBiologicalSex  = sex
            hkDateOfBirth    = dob
            hkLatestWeightKg = mass
            hkLatestHeightCm = height
        }
    }

    private func fetchLatestBodyMassKg() async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return 0 }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, s, _ in
                let kg = (s?.first as? HKQuantitySample)?.quantity.doubleValue(for: .gramUnit(with: .kilo)) ?? 0
                cont.resume(returning: kg)
            }
            store.execute(q)
        }
    }

    private func fetchLatestHeightCm() async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .height) else { return 0 }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        return await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, s, _ in
                let cm = (s?.first as? HKQuantitySample)?.quantity.doubleValue(for: .meterUnit(with: .centi)) ?? 0
                cont.resume(returning: cm)
            }
            store.execute(q)
        }
    }

    /// Builds a ProfileSnapshot preferring Apple-Health values, falling back to manually
    /// maintained UserSettings if the Health data is missing.
    func profileSnapshot(settings: UserSettings) -> ProfileSnapshot {
        let age: Int = {
            if let comps = hkDateOfBirth,
               let birth = Calendar.current.date(from: comps),
               let years = Calendar.current.dateComponents([.year], from: birth, to: Date()).year,
               years > 0 {
                return years
            }
            return settings.ageYears
        }()

        let weight = hkLatestWeightKg > 0 ? hkLatestWeightKg : settings.weightKg
        let height = hkLatestHeightCm > 0 ? hkLatestHeightCm : settings.heightCm

        let sex: BiologicalSex = {
            switch hkBiologicalSex {
            case .male:   return .male
            case .female: return .female
            default:      return .unspecified
            }
        }()

        return ProfileSnapshot(ageYears: age, weightKg: weight, heightCm: height, sex: sex)
    }

    // MARK: - Today

    func refreshTodayData() async {
        async let steps        = fetchTodaySum(.stepCount,              unit: .count())
        async let calories     = fetchTodaySum(.activeEnergyBurned,     unit: .kilocalorie())
        async let distRun      = fetchTodaySum(.distanceWalkingRunning, unit: .meter())
        async let distCycle    = fetchTodaySum(.distanceCycling,        unit: .meter())
        let (s, c, dr, dc)     = await (steps, calories, distRun, distCycle)
        await MainActor.run {
            todaySteps       = Int(s)
            todayCalories    = c
            todayDistanceKm  = (dr + dc) / 1_000
        }
    }

    // MARK: - Statistics

    func fetchDailyStats(for date: Date) async -> (steps: Int, calories: Double, distanceKm: Double) {
        let cal   = Calendar.current
        let start = cal.startOfDay(for: date)
        let end   = cal.date(byAdding: .day, value: 1, to: start)!
        async let s  = fetchSum(.stepCount,              unit: .count(),      start: start, end: end)
        async let c  = fetchSum(.activeEnergyBurned,     unit: .kilocalorie(), start: start, end: end)
        async let dr = fetchSum(.distanceWalkingRunning, unit: .meter(),      start: start, end: end)
        async let dc = fetchSum(.distanceCycling,        unit: .meter(),      start: start, end: end)
        let (steps, cal2, dr2, dc2) = await (s, c, dr, dc)
        return (Int(steps), cal2, (dr2 + dc2) / 1_000)
    }

    func fetchPeriodStats(days: Int) async -> [(date: Date, steps: Int, calories: Double, distanceKm: Double)] {
        let today = Calendar.current.startOfDay(for: Date())
        var result: [(date: Date, steps: Int, calories: Double, distanceKm: Double)] = []
        for i in (0..<days).reversed() {
            guard let date = Calendar.current.date(byAdding: .day, value: -i, to: today) else { continue }
            let s = await fetchDailyStats(for: date)
            result.append((date: date, steps: s.steps, calories: s.calories, distanceKm: s.distanceKm))
        }
        return result
    }

    // MARK: - Workouts

    func loadWorkouts() async {
        await MainActor.run { isLoading = true }
        let hkList = await fetchAllHKWorkouts()

        // Commit minimal records immediately — same two-phase strategy as
        // fullImportFromHealth, so users never see a mysteriously empty list.
        var records: [WorkoutRecord] = hkList.map { minimalRecord(from: $0) }
        await MainActor.run {
            workouts  = records
            isLoading = false
        }

        // Enrich in background (routes / HR / steps).
        for (i, hw) in hkList.enumerated() {
            let enriched: WorkoutRecord? = try? await withThrowingTimeout(seconds: 30) {
                await self.enrichRecord(records[i], from: hw)
            }
            if let e = enriched {
                records[i] = e
                let snapshot = records
                await MainActor.run { workouts = snapshot }
            }
        }
    }

    func importAllWorkouts() async {
        await loadWorkouts()
        await refreshTodayData()
    }

    /// Full re-import of every workout stored in Apple Health, with progress.
    ///
    /// Two-phase strategy so that NO workout is ever dropped:
    ///   Phase 1 — build a minimal record for every HKWorkout (only the
    ///             synchronous properties HK gives us directly). Commit to
    ///             `self.workouts` immediately so the user sees every workout
    ///             right away, even if enrichment fails later.
    ///   Phase 2 — enrich each record with route / heart-rate / steps, each
    ///             call individually bounded by a timeout so a single bad
    ///             workout can't stall the whole import. Commit updates
    ///             incrementally after every workout.
    func fullImportFromHealth() async {
        await MainActor.run {
            importInProgress   = true
            importProgress     = 0
            importStatus       = lt("Lese Workouts aus Apple Health…")
            importedCount      = 0
            importedRouteCount = 0
        }

        // Re-request authorization in case the user dismissed the first prompt.
        try? await store.requestAuthorization(toShare: writeTypes, read: readTypes)

        // ── Phase 1: fetch every HKWorkout ──────────────────────────────
        let hkList: [HKWorkout] = await fetchAllHKWorkouts()
        print("[HealthKit] fetched \(hkList.count) HKWorkouts from HealthKit")

        // Per-source breakdown so it's obvious — in the console AND in the UI
        // — whether the OS actually handed us all sources. If the user expects
        // to see e.g. Garmin Connect workouts and that row says 0, the problem
        // is iOS-level authorization, not our code.
        var sourceCounts: [String: Int] = [:]
        for hw in hkList { sourceCounts[hw.sourceRevision.source.name, default: 0] += 1 }
        print("[HealthKit] sources: \(sourceCounts)")
        let breakdown = sourceCounts
            .map { (name: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
        await MainActor.run { importSourceBreakdown = breakdown }

        // Minimal records — purely synchronous, nothing to hang on.
        var records: [WorkoutRecord] = hkList.map { minimalRecord(from: $0) }

        await MainActor.run {
            workouts           = records
            importedCount      = records.count
            importProgress     = hkList.isEmpty ? 1 : 0.15
            importStatus       = lf("%d Workouts importiert – werte Details aus…", records.count)
        }

        // ── Phase 2: enrich each record with route / HR / steps ─────────
        var routeHits = 0
        for (i, hw) in hkList.enumerated() {
            let srcName = hw.sourceRevision.source.name
            // Whole-workout timeout (30 s) as last-line defense.
            let enriched: WorkoutRecord? = try? await withThrowingTimeout(seconds: 30) {
                await self.enrichRecord(records[i], from: hw)
            }
            if let e = enriched {
                records[i] = e
                if !e.route.isEmpty { routeHits += 1 }
            } else {
                print("[HealthKit] ⚠️ enrichment timed out for \(srcName) @ \(hw.startDate) — keeping minimal record")
            }

            let progress  = 0.15 + 0.85 * Double(i + 1) / Double(max(hkList.count, 1))
            let snapshot  = records
            let routes    = routeHits
            await MainActor.run {
                workouts           = snapshot
                importProgress     = progress
                importedCount      = snapshot.count
                importedRouteCount = routes
                importStatus       = lf("Details %d/%d • %@", i + 1, hkList.count, srcName)
            }
        }

        let finalSnapshot = records
        let finalRoutes   = routeHits
        await MainActor.run {
            workouts           = finalSnapshot
            importProgress     = 1
            importedCount      = finalSnapshot.count
            importedRouteCount = finalRoutes
            importStatus       = lf("Fertig: %d Workouts (%d mit Route).", finalSnapshot.count, finalRoutes)
            isLoading          = false
            importInProgress   = false
        }
        await refreshTodayData()
    }

    /// Fetch every HKWorkout Apple Health is willing to give us.
    ///
    /// Uses THREE independent strategies and deduplicates the union by UUID —
    /// because HealthKit has well-documented edge cases where a single
    /// `HKSampleQuery(predicate: nil)` returns fewer samples than querying
    /// each source individually.
    ///
    /// Strategy A: global query with nil predicate (the obvious one).
    /// Strategy B: global query with an explicit `distantPast…distantFuture`
    ///             date predicate — some older HK builds silently bound nil
    ///             predicates to the last year.
    /// Strategy C: enumerate every source that has written workouts via
    ///             `HKSourceQuery`, then one `HKSampleQuery` per source.
    ///             This catches samples that the global query drops and
    ///             also gives us a real per-source diagnostic.
    private func fetchAllHKWorkouts() async -> [HKWorkout] {
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        // --- Strategy A: nil predicate -------------------------------------
        let a = await sampleQuery(predicate: nil, sort: sort)
        print("[HealthKit] strategy A (nil predicate): \(a.count) workouts")

        // --- Strategy B: distantPast … distantFuture predicate -------------
        let widePred = HKQuery.predicateForSamples(
            withStart: .distantPast,
            end:       .distantFuture,
            options:   []
        )
        let b = await sampleQuery(predicate: widePred, sort: sort)
        print("[HealthKit] strategy B (wide date predicate): \(b.count) workouts")

        // --- Strategy C: per-source ---------------------------------------
        let sources = await allWorkoutSources()
        print("[HealthKit] strategy C: \(sources.count) sources discovered:")
        var c: [HKWorkout] = []
        for src in sources {
            let pred = HKQuery.predicateForObjects(from: src)
            let samples = await sampleQuery(predicate: pred, sort: sort)
            print("[HealthKit]   • \(src.name) [\(src.bundleIdentifier)]: \(samples.count)")
            c.append(contentsOf: samples)
        }

        // --- Union + dedupe by UUID ---------------------------------------
        var seen = Set<UUID>()
        var union: [HKWorkout] = []
        for list in [a, b, c] {
            for hw in list where seen.insert(hw.uuid).inserted {
                union.append(hw)
            }
        }
        union.sort { $0.startDate > $1.startDate }
        print("[HealthKit] union after dedupe: \(union.count) workouts (A=\(a.count), B=\(b.count), C=\(c.count))")
        return union
    }

    /// Single HKSampleQuery helper used by the multi-strategy fetcher.
    private func sampleQuery(predicate: NSPredicate?, sort: NSSortDescriptor) async -> [HKWorkout] {
        await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: .workoutType(),
                                  predicate: predicate,
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [sort]) { _, s, err in
                if let err { print("[HealthKit] sampleQuery error: \(err)") }
                cont.resume(returning: (s as? [HKWorkout]) ?? [])
            }
            store.execute(q)
        }
    }

    /// Enumerate every source (app/device) that has ever written a workout.
    private func allWorkoutSources() async -> [HKSource] {
        await withCheckedContinuation { cont in
            let q = HKSourceQuery(sampleType: .workoutType(),
                                  samplePredicate: nil) { _, sources, err in
                if let err { print("[HealthKit] sourceQuery error: \(err)") }
                cont.resume(returning: Array(sources ?? []))
            }
            store.execute(q)
        }
    }

    /// Build a `WorkoutRecord` from an HKWorkout using only synchronous
    /// properties — nothing here can hang, so every workout survives to
    /// Phase 2 regardless of HK responsiveness.
    private func minimalRecord(from hw: HKWorkout) -> WorkoutRecord {
        let type = mapActivityType(hw.workoutActivityType)
        let distance: Double = {
            if let d = hw.totalDistance?.doubleValue(for: .meter()), d > 0 { return d }
            if let stat = hw.statistics(for: HKQuantityType(.distanceWalkingRunning)),
               let q = stat.sumQuantity() { return q.doubleValue(for: .meter()) }
            if let stat = hw.statistics(for: HKQuantityType(.distanceCycling)),
               let q = stat.sumQuantity() { return q.doubleValue(for: .meter()) }
            if let stat = hw.statistics(for: HKQuantityType(.distanceSwimming)),
               let q = stat.sumQuantity() { return q.doubleValue(for: .meter()) }
            return 0
        }()
        let calories: Double = {
            if let c = hw.totalEnergyBurned?.doubleValue(for: .kilocalorie()), c > 0 { return c }
            if let stat = hw.statistics(for: HKQuantityType(.activeEnergyBurned)),
               let q = stat.sumQuantity() { return q.doubleValue(for: .kilocalorie()) }
            return 0
        }()
        let duration = hw.duration
        return WorkoutRecord(
            id: UUID(), workoutType: type,
            startDate: hw.startDate, endDate: hw.endDate,
            steps: 0,
            activeCalories: calories,
            distanceMeters: distance,
            route: [],
            averageSpeedMPS: duration > 0 && distance > 0 ? distance / duration : 0,
            maxSpeedMPS: 0,
            heartRateAvg: 0,
            hkWorkoutUUID: hw.uuid
        )
    }

    /// Enrich a minimal record with route, heart rate and step count. Each
    /// sub-query is individually bounded to avoid blocking.
    private func enrichRecord(_ base: WorkoutRecord, from hw: HKWorkout) async -> WorkoutRecord {
        // Route (with its own 15 s timeout inside fetchRoute wrapper).
        let route: [RoutePoint] = await {
            if let key = hw.metadata?["SimpleTrackingRouteID"] as? String,
               let cached = RouteCache.shared.route(forKey: key) {
                return cached
            }
            return (try? await withThrowingTimeout(seconds: 15) {
                await self.fetchRoute(for: hw)
            }) ?? []
        }()

        // Steps (bounded)
        let steps: Double = (try? await withThrowingTimeout(seconds: 8) {
            await self.fetchSum(.stepCount, unit: .count(), start: hw.startDate, end: hw.endDate)
        }) ?? 0

        // Heart rate (bounded)
        let heartRate: Double = (try? await withThrowingTimeout(seconds: 8) {
            await self.fetchAvgHeartRate(start: hw.startDate, end: hw.endDate)
        }) ?? 0

        let maxSpeed = route.map(\.speed).max() ?? 0

        print(
            "[HealthKit] enriched \(hw.workoutActivityType.rawValue) from \(hw.sourceRevision.source.name) @ \(hw.startDate): " +
            "distance=\(Int(base.distanceMeters))m routePoints=\(route.count) steps=\(Int(steps)) hr=\(Int(heartRate))"
        )

        return WorkoutRecord(
            id: base.id, workoutType: base.workoutType,
            startDate: base.startDate, endDate: base.endDate,
            steps: Int(steps),
            activeCalories: base.activeCalories,
            distanceMeters: base.distanceMeters,
            route: route,
            averageSpeedMPS: base.averageSpeedMPS,
            maxSpeedMPS: maxSpeed,
            heartRateAvg: heartRate,
            hkWorkoutUUID: base.hkWorkoutUUID
        )
    }

    func fetchRoute(for workout: HKWorkout) async -> [RoutePoint] {
        let routes: [HKWorkoutRoute] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: HKSeriesType.workoutRoute(),
                                  predicate: HKQuery.predicateForObjects(from: workout),
                                  limit: HKObjectQueryNoLimit,
                                  sortDescriptors: nil) { _, s, _ in
                cont.resume(returning: (s as? [HKWorkoutRoute]) ?? [])
            }
            store.execute(q)
        }
        print(
            "[HealthKit] route samples for \(workout.sourceRevision.source.name) @ \(workout.startDate): \(routes.count)"
        )
        // Process ALL route segments (not just the first) — pauses/multi-part
        // workouts from other apps often split into several route series.
        var points: [RoutePoint] = []
        for route in routes {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                var done = false
                let q = HKWorkoutRouteQuery(route: route) { _, locs, finished, err in
                    if let locs {
                        points.append(contentsOf: locs.map { RoutePoint(location: $0) })
                    }
                    // Resume on finished OR error — never block forever.
                    if (finished || err != nil) && !done {
                        done = true
                        cont.resume()
                    }
                }
                store.execute(q)
            }
        }
        print(
            "[HealthKit] route points for \(workout.sourceRevision.source.name) @ \(workout.startDate): \(points.count)"
        )
        return points
    }

    // MARK: - Delete

    /// Delete a single workout. Works for workouts we wrote (full delete) and
    /// for imported workouts that we only reference by hkWorkoutUUID — in the
    /// second case we can only remove it from the in-memory list (HK won't
    /// let us delete another app's sample).
    @discardableResult
    func deleteWorkout(_ record: WorkoutRecord) async -> Bool {
        var hkDeleted = false
        if let uuid = record.hkWorkoutUUID {
            // Look up the underlying HKWorkout by UUID.
            let pred = HKQuery.predicateForObject(with: uuid)
            let found: [HKWorkout] = await withCheckedContinuation { cont in
                let q = HKSampleQuery(sampleType: .workoutType(),
                                      predicate: pred,
                                      limit: 1,
                                      sortDescriptors: nil) { _, s, _ in
                    cont.resume(returning: (s as? [HKWorkout]) ?? [])
                }
                store.execute(q)
            }
            if let hw = found.first {
                do {
                    try await store.delete(hw)
                    hkDeleted = true
                } catch {
                    print("[HealthKit] delete failed (likely not our sample): \(error.localizedDescription)")
                }
            }
        }
        await MainActor.run {
            workouts.removeAll { $0.id == record.id }
        }
        return hkDeleted
    }

    // MARK: - Save

    func saveWorkout(
        type: WorkoutType, start: Date, end: Date,
        steps: Int, calories: Double, distanceMeters: Double,
        routePoints: [RoutePoint]
    ) async throws {
        let workout = HKWorkout(
            activityType: type.hkWorkoutActivityType,
            start: start, end: end,
            duration: end.timeIntervalSince(start),
            totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: calories),
            totalDistance: HKQuantity(unit: .meter(), doubleValue: distanceMeters),
            metadata: nil
        )
        try await store.save(workout)

        // Separate Quantity-Samples, damit Tages-Aggregate (Schritte,
        // Aktiv-Kalorien, Distanz) Apple Health sofort korrekt erreichen.
        // HKWorkout.totalEnergyBurned/totalDistance allein reicht iOS nicht
        // immer aus, um sie in den Tagessummen zu führen.
        var samples: [HKQuantitySample] = []

        if steps > 0, let t = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            samples.append(HKQuantitySample(type: t,
                quantity: HKQuantity(unit: .count(), doubleValue: Double(steps)),
                start: start, end: end))
        }
        if calories > 0, let t = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            samples.append(HKQuantitySample(type: t,
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: calories),
                start: start, end: end))
        }
        if distanceMeters > 0 {
            let id: HKQuantityTypeIdentifier = (type == .cycling) ? .distanceCycling : .distanceWalkingRunning
            if let t = HKQuantityType.quantityType(forIdentifier: id) {
                samples.append(HKQuantitySample(type: t,
                    quantity: HKQuantity(unit: .meter(), doubleValue: distanceMeters),
                    start: start, end: end))
            }
        }
        if !samples.isEmpty {
            try await store.save(samples)
        }

        if routePoints.count >= 2 {
            let builder = HKWorkoutRouteBuilder(healthStore: store, device: nil)
            try await builder.insertRouteData(routePoints.map(\.clLocation))
            try await builder.finishRoute(with: workout, metadata: nil)
        }

        await loadWorkouts()
        await refreshTodayData()

        if let newest = workouts.first {
            Task { await CloudKitService.shared.publishWorkoutIfNeeded(newest) }
        }
    }

    // MARK: - Nutrition Writes

    /// Schreibt einen FoodEntry nach Apple Health und gibt die UUIDs der
    /// erzeugten Samples als Strings zurück — die hält der FoodLogStore in
    /// `FoodEntry.healthKitSampleIDs` fest, damit wir beim Löschen in der
    /// App auch die Health-Samples wieder entfernen können.
    @discardableResult
    func writeFoodSamples(for entry: FoodEntry) async -> [String] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        var saved: [HKQuantitySample] = []
        let end = entry.timestamp
        let nutrition = entry.resolvedNutrition

        if nutrition.calories > 0,
           let t = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed) {
            saved.append(HKQuantitySample(type: t,
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: nutrition.calories),
                start: end, end: end,
                metadata: [HKMetadataKeyFoodType: entry.name]))
        }
        if nutrition.carbsGrams > 0,
           let t = HKQuantityType.quantityType(forIdentifier: .dietaryCarbohydrates) {
            saved.append(HKQuantitySample(type: t,
                quantity: HKQuantity(unit: .gram(), doubleValue: nutrition.carbsGrams),
                start: end, end: end,
                metadata: [HKMetadataKeyFoodType: entry.name]))
        }
        // Wasser-Äquivalent nur für Getränke (Milliliter).
        if entry.kind == .drink,
           let ml = entry.portionMilliliters, ml > 0,
           let t = HKQuantityType.quantityType(forIdentifier: .dietaryWater) {
            saved.append(HKQuantitySample(type: t,
                quantity: HKQuantity(unit: .literUnit(with: .milli), doubleValue: ml),
                start: end, end: end,
                metadata: [HKMetadataKeyFoodType: entry.name]))
        }

        guard !saved.isEmpty else { return [] }
        do {
            try await store.save(saved)
            return saved.map { $0.uuid.uuidString }
        } catch {
            print("[HealthKit] writeFoodSamples failed: \(error.localizedDescription)")
            return []
        }
    }

    /// Löscht zuvor geschriebene Food-Samples aus Apple Health.
    func deleteFoodSamples(uuids: [String]) async {
        guard !uuids.isEmpty, HKHealthStore.isHealthDataAvailable() else { return }
        let ids: [UUID] = uuids.compactMap(UUID.init)
        guard !ids.isEmpty else { return }
        let pred = HKQuery.predicateForObjects(with: Set(ids))
        let types: [HKQuantityTypeIdentifier] = [.dietaryEnergyConsumed, .dietaryCarbohydrates, .dietaryWater]
        for id in types {
            guard let t = HKQuantityType.quantityType(forIdentifier: id) else { continue }
            do {
                try await store.deleteObjects(of: t, predicate: pred)
            } catch {
                // Irrelevant — Sample war vielleicht nicht von uns.
            }
        }
    }

    // MARK: - Body Metrics Writes

    /// Schreibt Körpergewicht nach Health. Nur aufrufen, wenn der Wert
    /// deutlich vom letzten Health-Wert abweicht (siehe UserSettings).
    func writeBodyMass(kg: Double, at date: Date = Date()) async {
        guard kg > 0, HKHealthStore.isHealthDataAvailable(),
              let t = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return }
        let sample = HKQuantitySample(type: t,
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg),
            start: date, end: date)
        do {
            try await store.save(sample)
            await MainActor.run { self.hkLatestWeightKg = kg }
        } catch {
            print("[HealthKit] writeBodyMass failed: \(error.localizedDescription)")
        }
    }

    /// Schreibt Körpergröße nach Health.
    func writeHeight(cm: Double, at date: Date = Date()) async {
        guard cm > 0, HKHealthStore.isHealthDataAvailable(),
              let t = HKQuantityType.quantityType(forIdentifier: .height) else { return }
        let sample = HKQuantitySample(type: t,
            quantity: HKQuantity(unit: .meterUnit(with: .centi), doubleValue: cm),
            start: date, end: date)
        do {
            try await store.save(sample)
            await MainActor.run { self.hkLatestHeightCm = cm }
        } catch {
            print("[HealthKit] writeHeight failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Helpers

    private func fetchTodaySum(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double {
        let start = Calendar.current.startOfDay(for: Date())
        return await fetchSum(id, unit: unit, start: start, end: Date())
    }

    private func fetchSum(_ id: HKQuantityTypeIdentifier, unit: HKUnit, start: Date, end: Date) async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return 0 }
        let pred = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: pred, options: .cumulativeSum) { _, r, _ in
                cont.resume(returning: r?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            store.execute(q)
        }
    }

    private func fetchAvgHeartRate(start: Date, end: Date) async -> Double {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return 0 }
        let pred = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: pred, options: .discreteAverage) { _, r, _ in
                cont.resume(returning: r?.averageQuantity()?.doubleValue(for: HKUnit(from: "count/min")) ?? 0)
            }
            store.execute(q)
        }
    }

    private func mapActivityType(_ type: HKWorkoutActivityType) -> WorkoutType {
        switch type {
        // Running
        case .running, .trackAndField, .wheelchairRunPace:
            return .running

        // Walking
        case .walking, .wheelchairWalkPace:
            return .walking

        // Cycling
        case .cycling, .handCycling:
            return .cycling

        // Hiking / climbing
        case .hiking, .climbing:
            return .hiking

        // Swimming & water
        case .swimming, .waterFitness, .waterPolo, .waterSports,
             .surfingSports, .sailing:
            return .swimming

        // Rowing & paddle
        case .rowing, .paddleSports:
            return .rowing

        // Cardio machines
        case .elliptical:
            return .elliptical

        // Stairs
        case .stairs, .stairClimbing, .stepTraining:
            return .stairs

        // Yoga / mobility / mind-body
        case .yoga, .pilates, .mindAndBody, .flexibility,
             .taiChi, .preparationAndRecovery, .cooldown:
            return .yoga

        // Strength / combat
        case .traditionalStrengthTraining, .functionalStrengthTraining,
             .coreTraining, .boxing, .martialArts, .kickboxing, .wrestling,
             .gymnastics:
            return .strength

        // HIIT / high-intensity / mixed cardio
        case .highIntensityIntervalTraining, .jumpRope,
             .crossTraining, .mixedCardio, .fitnessGaming:
            return .hiit

        // Dance
        case .cardioDance, .socialDance, .barre:
            return .dance

        // Racquet sports
        case .tennis, .tableTennis, .badminton, .squash,
             .racquetball, .pickleball:
            return .tennis

        // Football / soccer
        case .soccer, .americanFootball, .australianFootball, .rugby:
            return .soccer

        // Court / team ball sports
        case .basketball, .volleyball, .handball:
            return .basketball

        // Golf
        case .golf:
            return .golf

        // Skating / skateboarding
        case .skatingSports:
            return .skating

        // Snow sports
        case .downhillSkiing, .snowboarding, .snowSports, .crossCountrySkiing:
            return .skiing

        // Everything else (archery, bowling, baseball, cricket, fishing,
        // hunting, equestrian, disc sports, play, …) — keep the workout,
        // don't silently drop it.
        default:
            print("[HealthKit] unmapped activity type rawValue=\(type.rawValue) → .other")
            return .other
        }
    }
}

// MARK: - Timeout helper

enum TimeoutError: Error { case timedOut }

/// Runs `operation` but aborts with `TimeoutError.timedOut` if it doesn't
/// complete within `seconds`. Used to ensure no single HealthKit query can
/// stall the whole import.
private func withThrowingTimeout<T: Sendable>(
    seconds: Double,
    operation: @escaping @Sendable () async -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError.timedOut
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
