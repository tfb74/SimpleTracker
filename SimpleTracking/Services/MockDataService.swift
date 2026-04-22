import Foundation
import HealthKit
import CoreLocation

@Observable
final class MockDataService {
    static let shared = MockDataService()
    private let store = HKHealthStore()

    var isGenerating   = false
    var progress: Double = 0
    var statusMessage  = ""

    private init() {}

    // MARK: - Delete All Health Data

    func deleteAll() async {
        await MainActor.run { statusMessage = "Lösche alte Daten…" }
        RouteCache.shared.removeAll()

        // 1. Delete all workouts (HealthKit cascades associated routes)
        let workouts: [HKWorkout] = await withCheckedContinuation { cont in
            let q = HKSampleQuery(sampleType: .workoutType(), predicate: nil,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, s, _ in
                cont.resume(returning: (s as? [HKWorkout]) ?? [])
            }
            store.execute(q)
        }
        if !workouts.isEmpty { try? await store.delete(workouts) }

        // 2. Delete quantity samples from the last 35 days
        let since = Calendar.current.date(byAdding: .day, value: -35, to: Date())!
        let pred  = HKQuery.predicateForSamples(withStart: since, end: Date())
        let ids: [HKQuantityTypeIdentifier] = [
            .stepCount, .activeEnergyBurned,
            .distanceWalkingRunning, .distanceCycling, .heartRate
        ]
        for id in ids {
            guard let type = HKQuantityType.quantityType(forIdentifier: id) else { continue }
            let samples: [HKSample] = await withCheckedContinuation { cont in
                let q = HKSampleQuery(sampleType: type, predicate: pred,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, s, _ in
                    cont.resume(returning: s ?? [])
                }
                store.execute(q)
            }
            if !samples.isEmpty { try? await store.delete(samples) }
        }
    }

    // MARK: - Public Entry Point

    /// Creates ONE complete running workout with a dense GPS route.
    /// Used to verify end-to-end route rendering.
    func generateOne() async {
        await MainActor.run { isGenerating = true; progress = 0; statusMessage = "Erstelle 1 Lauf-Workout mit Route…" }

        let route = runningRoutes[0]                         // Englischer Garten
        let coords = interpolated(route, stepMeters: 12)
        let start  = Calendar.current.date(byAdding: .hour, value: -3, to: Date())!
        let locs   = buildLocations(from: coords, startDate: start, type: .running)

        if locs.count >= 2 {
            let end      = locs.last!.timestamp
            let distance = totalDistance(locs)
            let duration = end.timeIntervalSince(start)
            let profile  = HealthKitService.shared.profileSnapshot(settings: UserSettings.shared)
            let calories = CaloricEstimator.estimate(type: .running,
                                                     distanceMeters: distance,
                                                     durationSec: duration,
                                                     profile: profile)
            let steps    = Int(distance / 0.78)
            let avgHR    = 165.0
            try? await saveWorkout(type: .running, start: start, end: end,
                                   distance: distance, calories: calories,
                                   steps: steps, heartRate: avgHR, locations: locs)
            print("[MockData] generateOne: saved workout with \(locs.count) GPS points, distance=\(Int(distance))m")
        } else {
            print("[MockData] generateOne: FAILED – locs.count=\(locs.count)")
        }

        await MainActor.run { statusMessage = "Schreibe 30 Tage Schritt- & Kaloriendaten…" }
        await writeDailyQuantities()

        await MainActor.run {
            progress       = 1.0
            isGenerating   = false
            statusMessage  = "✅ 1 Workout + 30 Tage Statistik erstellt."
        }
    }

    /// Builds a WorkoutRecord entirely in memory (no HealthKit writes).
    /// Used to preview route rendering without requiring HK permissions.
    func buildPreviewRecord() -> WorkoutRecord {
        let route    = runningRoutes[0]
        let coords   = interpolated(route, stepMeters: 12)
        let start    = Calendar.current.date(byAdding: .hour, value: -3, to: Date())!
        let locs     = buildLocations(from: coords, startDate: start, type: .running)
        let distance = totalDistance(locs)
        let end      = locs.last?.timestamp ?? start.addingTimeInterval(1800)
        let duration = end.timeIntervalSince(start)
        let avgSpeed = duration > 0 ? distance / duration : 0
        let maxSpeed = locs.map(\.speed).max() ?? avgSpeed
        return WorkoutRecord(
            id: UUID(),
            workoutType: .running,
            startDate: start,
            endDate: end,
            steps: Int(distance / 0.78),
            activeCalories: CaloricEstimator.estimate(
                type: .running, distanceMeters: distance, durationSec: duration,
                profile: HealthKitService.shared.profileSnapshot(settings: UserSettings.shared)
            ),
            distanceMeters: distance,
            route: locs.map { RoutePoint(location: $0) },
            averageSpeedMPS: avgSpeed,
            maxSpeedMPS: maxSpeed,
            heartRateAvg: 165.0,
            hkWorkoutUUID: nil
        )
    }

    func generateAll() async {
        await MainActor.run { isGenerating = true; progress = 0 }

        await status("Schreibe 30 Tage Schritt- & Kaloriendaten…")
        await writeDailyQuantities()
        await step(0.20)

        await status("Erstelle Lauf-Workouts (9)…")
        await writeWorkouts(type: .running, routes: runningRoutes, count: 9)
        await step(0.45)

        await status("Erstelle Geh-Workouts (7)…")
        await writeWorkouts(type: .walking, routes: walkingRoutes, count: 7)
        await step(0.65)

        await status("Erstelle Rad-Workouts (6)…")
        await writeWorkouts(type: .cycling, routes: cyclingRoutes, count: 6)
        await step(0.82)

        await status("Erstelle Wander-Workouts (5)…")
        await writeWorkouts(type: .hiking, routes: hikingRoutes, count: 5)
        await step(1.0)

        await status("✅ 27 Workouts + 30 Tage Daten erstellt.")
        await MainActor.run { isGenerating = false }
    }

    // MARK: - Daily Quantities (30 days)

    private func writeDailyQuantities() async {
        let cal   = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard
            let stepType  = HKQuantityType.quantityType(forIdentifier: .stepCount),
            let calType   = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
            let distType  = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)
        else { return }

        var samples: [HKSample] = []
        for offset in (0..<30).reversed() {
            guard let dayStart = cal.date(byAdding: .day, value: -offset, to: today),
                  let dayEnd   = cal.date(byAdding: .day, value: 1, to: dayStart) else { continue }
            let weekday  = cal.component(.weekday, from: dayStart)
            let weekend  = weekday == 1 || weekday == 7
            let steps    = Double(Int.random(in: weekend ? 9_500...18_000 : 5_000...12_500))
            let calories = steps * Double.random(in: 0.042...0.058)
            let distM    = steps * Double.random(in: 0.65...0.80)
            samples.append(HKQuantitySample(type: stepType,
                quantity: HKQuantity(unit: .count(), doubleValue: steps), start: dayStart, end: dayEnd))
            samples.append(HKQuantitySample(type: calType,
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: calories), start: dayStart, end: dayEnd))
            samples.append(HKQuantitySample(type: distType,
                quantity: HKQuantity(unit: .meter(), doubleValue: distM), start: dayStart, end: dayEnd))
        }
        try? await store.save(samples)
    }

    // MARK: - Workout Generator

    private func writeWorkouts(type: WorkoutType, routes: [[CLLocationCoordinate2D]], count: Int) async {
        let cal   = Calendar.current
        let today = cal.startOfDay(for: Date())
        // Spread evenly across last 28 days, one per 2-3 days max
        let daySlots = stride(from: 1, through: 28, by: max(1, 28 / count)).map { $0 }

        for i in 0..<count {
            let daysBack = i < daySlots.count ? daySlots[i] : Int.random(in: 1...28)
            guard let workoutDate = cal.date(byAdding: .day, value: -daysBack, to: today) else { continue }
            let hour = Int.random(in: 6...20)
            guard let startDate = cal.date(bySettingHour: hour, minute: Int.random(in: 0...55), second: 0, of: workoutDate) else { continue }

            // Pick route, apply small jitter so each workout looks slightly different
            let baseRoute = routes[i % routes.count]
            let jitterAmt = 0.0005 * Double((i % 4) + 1)
            let coords    = interpolated(jittered(baseRoute, spread: jitterAmt), stepMeters: 12)

            let locs = buildLocations(from: coords, startDate: startDate, type: type)
            guard locs.count >= 2 else { continue }

            let endDate  = locs.last!.timestamp
            let distance = totalDistance(locs)
            let duration = endDate.timeIntervalSince(startDate)
            let profile  = HealthKitService.shared.profileSnapshot(settings: UserSettings.shared)
            let calories = CaloricEstimator.estimate(type: type, distanceMeters: distance,
                                                     durationSec: duration, profile: profile)
            let steps    = type == .cycling ? 0 : Int(distance / Double.random(in: 0.72...0.82))
            let avgHR    = Double(Int.random(in: heartRateRange(type)))

            try? await saveWorkout(
                type: type, start: startDate, end: endDate,
                distance: distance, calories: calories,
                steps: steps, heartRate: avgHR, locations: locs
            )
        }
    }

    private func saveWorkout(
        type: WorkoutType, start: Date, end: Date,
        distance: Double, calories: Double,
        steps: Int, heartRate: Double,
        locations: [CLLocation]
    ) async throws {
        guard
            let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount),
            let calType  = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
            let distType = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning),
            let hrType   = HKQuantityType.quantityType(forIdentifier: .heartRate)
        else { return }

        let routeKey = UUID().uuidString
        let workout = HKWorkout(
            activityType: type.hkWorkoutActivityType,
            start: start, end: end,
            duration: end.timeIntervalSince(start),
            totalEnergyBurned: HKQuantity(unit: .kilocalorie(), doubleValue: calories),
            totalDistance: HKQuantity(unit: .meter(), doubleValue: distance),
            metadata: ["SimpleTrackingRouteID": routeKey]
        )
        try await store.save(workout)

        // Cache the route IMMEDIATELY after successful workout save,
        // so later errors on quantity samples don't prevent route storage.
        if locations.count >= 2 {
            let routePoints = locations.map { RoutePoint(location: $0) }
            RouteCache.shared.setRoute(routePoints, forKey: routeKey)
        }

        // Quantity samples
        var samples: [HKSample] = []
        if steps > 0 {
            samples.append(HKQuantitySample(type: stepType,
                quantity: HKQuantity(unit: .count(), doubleValue: Double(steps)), start: start, end: end))
        }
        samples.append(HKQuantitySample(type: calType,
            quantity: HKQuantity(unit: .kilocalorie(), doubleValue: calories), start: start, end: end))
        if type != .cycling {
            samples.append(HKQuantitySample(type: distType,
                quantity: HKQuantity(unit: .meter(), doubleValue: distance), start: start, end: end))
        }

        // Heart rate: one sample per minute with ±8 bpm variance
        let hrUnit = HKUnit(from: "count/min")
        var t = start
        while t < end {
            let bpm = max(60, heartRate + Double.random(in: -8...8))
            samples.append(HKQuantitySample(type: hrType,
                quantity: HKQuantity(unit: hrUnit, doubleValue: bpm),
                start: t, end: t.addingTimeInterval(1)))
            t = t.addingTimeInterval(60)
        }
        try await store.save(samples)

    }

    // MARK: - Coordinate Interpolation

    /// Inserts intermediate coordinates every `stepMeters` along each segment.
    private func interpolated(_ coords: [CLLocationCoordinate2D], stepMeters: Double) -> [CLLocationCoordinate2D] {
        guard coords.count >= 2 else { return coords }
        var result: [CLLocationCoordinate2D] = [coords[0]]
        for i in 1..<coords.count {
            let from = coords[i - 1]
            let to   = coords[i]
            let fromLoc = CLLocation(latitude: from.latitude, longitude: from.longitude)
            let toLoc   = CLLocation(latitude: to.latitude,   longitude: to.longitude)
            let segmentDist = fromLoc.distance(from: toLoc)
            guard segmentDist > 0 else { continue }
            let steps = max(1, Int(segmentDist / stepMeters))
            for s in 1...steps {
                let f = Double(s) / Double(steps)
                result.append(CLLocationCoordinate2D(
                    latitude:  from.latitude  + (to.latitude  - from.latitude)  * f,
                    longitude: from.longitude + (to.longitude - from.longitude) * f
                ))
            }
        }
        return result
    }

    /// Adds small random noise to each coordinate.
    private func jittered(_ coords: [CLLocationCoordinate2D], spread: Double) -> [CLLocationCoordinate2D] {
        coords.map { CLLocationCoordinate2D(
            latitude:  $0.latitude  + Double.random(in: -spread...spread),
            longitude: $0.longitude + Double.random(in: -spread...spread)
        )}
    }

    /// Builds CLLocation objects with timestamps and realistic speed variance.
    private func buildLocations(from coords: [CLLocationCoordinate2D], startDate: Date, type: WorkoutType) -> [CLLocation] {
        guard coords.count >= 2 else { return [] }
        let speedRange = speedMPS(type)
        var locs: [CLLocation] = []
        var t = startDate

        // First point
        locs.append(CLLocation(coordinate: coords[0], altitude: altitude(type),
            horizontalAccuracy: Double.random(in: 3...6), verticalAccuracy: 5,
            course: 0, speed: Double.random(in: speedRange), timestamp: t))

        for i in 1..<coords.count {
            let prev = locs[i - 1]
            let prevCoord = coords[i - 1]
            let currCoord = coords[i]
            let d    = CLLocation(latitude: prevCoord.latitude, longitude: prevCoord.longitude)
                         .distance(from: CLLocation(latitude: currCoord.latitude, longitude: currCoord.longitude))
            let spd  = Double.random(in: speedRange)
            let dt   = d / spd
            t        = t.addingTimeInterval(dt)
            // Slight altitude variation for realism
            let alt  = prev.altitude + Double.random(in: -1.5...1.5)
            locs.append(CLLocation(
                coordinate: currCoord, altitude: alt,
                horizontalAccuracy: Double.random(in: 3...7),
                verticalAccuracy: Double.random(in: 3...8),
                course: bearing(from: prevCoord, to: currCoord),
                speed: spd, timestamp: t
            ))
        }
        return locs
    }

    private func totalDistance(_ locs: [CLLocation]) -> Double {
        guard locs.count >= 2 else { return 0 }
        return (1..<locs.count).reduce(0.0) { $0 + locs[$1].distance(from: locs[$1 - 1]) }
    }

    // MARK: - Helpers

    private func speedMPS(_ type: WorkoutType) -> ClosedRange<Double> {
        switch type {
        case .running: return 2.6...4.2
        case .walking: return 1.1...1.8
        case .cycling: return 4.4...8.5
        case .hiking:  return 0.7...1.3
        default:       return 1.0...2.0
        }
    }

    private func heartRateRange(_ type: WorkoutType) -> ClosedRange<Int> {
        switch type {
        case .running: return 148...178
        case .walking: return 92...118
        case .cycling: return 128...168
        case .hiking:  return 108...148
        default:       return 110...150
        }
    }

    private func altitude(_ type: WorkoutType) -> Double {
        switch type {
        case .running, .walking: return Double.random(in: 518...530)
        case .cycling:           return Double.random(in: 510...570)
        case .hiking:            return Double.random(in: 900...1_800)
        default:                 return Double.random(in: 500...600)
        }
    }

    /// Approximate bearing in degrees.
    private func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> CLLocationDirection {
        let dLon = b.longitude - a.longitude
        let y = sin(dLon * .pi / 180) * cos(b.latitude * .pi / 180)
        let x = cos(a.latitude * .pi / 180) * sin(b.latitude * .pi / 180)
              - sin(a.latitude * .pi / 180) * cos(b.latitude * .pi / 180) * cos(dLon * .pi / 180)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    private func status(_ msg: String) async { await MainActor.run { statusMessage = msg } }
    private func step(_ v: Double)   async { await MainActor.run { progress = v } }

    // MARK: - Route Definitions

    // ── Laufen ──────────────────────────────────────────────────────────────

    private var runningRoutes: [[CLLocationCoordinate2D]] { [
        // 1 · Englischer Garten: große Runde (~5.8 km)
        [
            .init(latitude: 48.1500, longitude: 11.5870),
            .init(latitude: 48.1520, longitude: 11.5905),
            .init(latitude: 48.1545, longitude: 11.5932),
            .init(latitude: 48.1572, longitude: 11.5950),
            .init(latitude: 48.1600, longitude: 11.5960),
            .init(latitude: 48.1628, longitude: 11.5958),
            .init(latitude: 48.1655, longitude: 11.5942),
            .init(latitude: 48.1678, longitude: 11.5915),
            .init(latitude: 48.1695, longitude: 11.5882),
            .init(latitude: 48.1705, longitude: 11.5845),
            .init(latitude: 48.1708, longitude: 11.5808),
            .init(latitude: 48.1700, longitude: 11.5772),
            .init(latitude: 48.1682, longitude: 11.5742),
            .init(latitude: 48.1658, longitude: 11.5722),
            .init(latitude: 48.1630, longitude: 11.5714),
            .init(latitude: 48.1602, longitude: 11.5720),
            .init(latitude: 48.1575, longitude: 11.5738),
            .init(latitude: 48.1552, longitude: 11.5762),
            .init(latitude: 48.1532, longitude: 11.5792),
            .init(latitude: 48.1518, longitude: 11.5828),
            .init(latitude: 48.1500, longitude: 11.5870),
        ],
        // 2 · Isar-Ufer Süd (~4.2 km)
        [
            .init(latitude: 48.1180, longitude: 11.5810),
            .init(latitude: 48.1210, longitude: 11.5822),
            .init(latitude: 48.1240, longitude: 11.5828),
            .init(latitude: 48.1270, longitude: 11.5820),
            .init(latitude: 48.1298, longitude: 11.5805),
            .init(latitude: 48.1322, longitude: 11.5782),
            .init(latitude: 48.1340, longitude: 11.5755),
            .init(latitude: 48.1322, longitude: 11.5728),
            .init(latitude: 48.1298, longitude: 11.5710),
            .init(latitude: 48.1268, longitude: 11.5705),
            .init(latitude: 48.1238, longitude: 11.5715),
            .init(latitude: 48.1210, longitude: 11.5730),
            .init(latitude: 48.1180, longitude: 11.5810),
        ],
        // 3 · Olympiapark Runde (~3.5 km)
        [
            .init(latitude: 48.1742, longitude: 11.5518),
            .init(latitude: 48.1762, longitude: 11.5545),
            .init(latitude: 48.1785, longitude: 11.5568),
            .init(latitude: 48.1808, longitude: 11.5578),
            .init(latitude: 48.1830, longitude: 11.5565),
            .init(latitude: 48.1845, longitude: 11.5540),
            .init(latitude: 48.1840, longitude: 11.5510),
            .init(latitude: 48.1822, longitude: 11.5488),
            .init(latitude: 48.1798, longitude: 11.5478),
            .init(latitude: 48.1772, longitude: 11.5488),
            .init(latitude: 48.1752, longitude: 11.5505),
            .init(latitude: 48.1742, longitude: 11.5518),
        ],
        // 4 · Nymphenburg Kanal & Park (~4.8 km)
        [
            .init(latitude: 48.1582, longitude: 11.5000),
            .init(latitude: 48.1598, longitude: 11.5040),
            .init(latitude: 48.1612, longitude: 11.5078),
            .init(latitude: 48.1625, longitude: 11.5115),
            .init(latitude: 48.1638, longitude: 11.5150),
            .init(latitude: 48.1650, longitude: 11.5185),
            .init(latitude: 48.1662, longitude: 11.5215),
            .init(latitude: 48.1672, longitude: 11.5245),
            .init(latitude: 48.1655, longitude: 11.5268),
            .init(latitude: 48.1632, longitude: 11.5252),
            .init(latitude: 48.1615, longitude: 11.5228),
            .init(latitude: 48.1598, longitude: 11.5200),
            .init(latitude: 48.1582, longitude: 11.5172),
            .init(latitude: 48.1568, longitude: 11.5140),
            .init(latitude: 48.1555, longitude: 11.5108),
            .init(latitude: 48.1565, longitude: 11.5072),
            .init(latitude: 48.1580, longitude: 11.5038),
            .init(latitude: 48.1582, longitude: 11.5000),
        ],
    ]}

    // ── Gehen ────────────────────────────────────────────────────────────────

    private var walkingRoutes: [[CLLocationCoordinate2D]] { [
        // 1 · Marienplatz / Altstadt (~2.5 km)
        [
            .init(latitude: 48.1374, longitude: 11.5755),
            .init(latitude: 48.1388, longitude: 11.5778),
            .init(latitude: 48.1402, longitude: 11.5800),
            .init(latitude: 48.1418, longitude: 11.5818),
            .init(latitude: 48.1435, longitude: 11.5825),
            .init(latitude: 48.1450, longitude: 11.5812),
            .init(latitude: 48.1458, longitude: 11.5792),
            .init(latitude: 48.1448, longitude: 11.5768),
            .init(latitude: 48.1432, longitude: 11.5750),
            .init(latitude: 48.1415, longitude: 11.5738),
            .init(latitude: 48.1398, longitude: 11.5742),
            .init(latitude: 48.1382, longitude: 11.5750),
            .init(latitude: 48.1374, longitude: 11.5755),
        ],
        // 2 · Westpark (~3.1 km)
        [
            .init(latitude: 48.1215, longitude: 11.5055),
            .init(latitude: 48.1232, longitude: 11.5082),
            .init(latitude: 48.1250, longitude: 11.5105),
            .init(latitude: 48.1268, longitude: 11.5120),
            .init(latitude: 48.1285, longitude: 11.5108),
            .init(latitude: 48.1295, longitude: 11.5082),
            .init(latitude: 48.1288, longitude: 11.5055),
            .init(latitude: 48.1270, longitude: 11.5038),
            .init(latitude: 48.1250, longitude: 11.5030),
            .init(latitude: 48.1232, longitude: 11.5040),
            .init(latitude: 48.1215, longitude: 11.5055),
        ],
        // 3 · Maxvorstadt Galerien (~2.2 km)
        [
            .init(latitude: 48.1492, longitude: 11.5682),
            .init(latitude: 48.1505, longitude: 11.5702),
            .init(latitude: 48.1518, longitude: 11.5718),
            .init(latitude: 48.1532, longitude: 11.5730),
            .init(latitude: 48.1545, longitude: 11.5718),
            .init(latitude: 48.1552, longitude: 11.5700),
            .init(latitude: 48.1545, longitude: 11.5680),
            .init(latitude: 48.1530, longitude: 11.5665),
            .init(latitude: 48.1515, longitude: 11.5660),
            .init(latitude: 48.1500, longitude: 11.5668),
            .init(latitude: 48.1492, longitude: 11.5682),
        ],
    ]}

    // ── Radfahren ────────────────────────────────────────────────────────────

    private var cyclingRoutes: [[CLLocationCoordinate2D]] { [
        // 1 · Isar-Radweg lang (Nord–Süd, ~14 km)
        [
            .init(latitude: 48.0650, longitude: 11.5558),
            .init(latitude: 48.0720, longitude: 11.5568),
            .init(latitude: 48.0790, longitude: 11.5572),
            .init(latitude: 48.0860, longitude: 11.5565),
            .init(latitude: 48.0930, longitude: 11.5550),
            .init(latitude: 48.1000, longitude: 11.5538),
            .init(latitude: 48.1068, longitude: 11.5530),
            .init(latitude: 48.1138, longitude: 11.5528),
            .init(latitude: 48.1205, longitude: 11.5535),
            .init(latitude: 48.1270, longitude: 11.5548),
            .init(latitude: 48.1205, longitude: 11.5535),
            .init(latitude: 48.1138, longitude: 11.5528),
            .init(latitude: 48.1068, longitude: 11.5530),
            .init(latitude: 48.1000, longitude: 11.5538),
            .init(latitude: 48.0930, longitude: 11.5550),
            .init(latitude: 48.0860, longitude: 11.5565),
            .init(latitude: 48.0790, longitude: 11.5572),
            .init(latitude: 48.0720, longitude: 11.5568),
            .init(latitude: 48.0650, longitude: 11.5558),
        ],
        // 2 · Starnberger See Runde (~22 km)
        [
            .init(latitude: 47.9998, longitude: 11.3408),
            .init(latitude: 48.0060, longitude: 11.3352),
            .init(latitude: 48.0125, longitude: 11.3300),
            .init(latitude: 48.0192, longitude: 11.3258),
            .init(latitude: 48.0258, longitude: 11.3225),
            .init(latitude: 48.0322, longitude: 11.3205),
            .init(latitude: 48.0385, longitude: 11.3195),
            .init(latitude: 48.0448, longitude: 11.3210),
            .init(latitude: 48.0508, longitude: 11.3248),
            .init(latitude: 48.0448, longitude: 11.3285),
            .init(latitude: 48.0385, longitude: 11.3312),
            .init(latitude: 48.0322, longitude: 11.3330),
            .init(latitude: 48.0258, longitude: 11.3348),
            .init(latitude: 48.0192, longitude: 11.3368),
            .init(latitude: 48.0125, longitude: 11.3390),
            .init(latitude: 48.0060, longitude: 11.3398),
            .init(latitude: 47.9998, longitude: 11.3408),
        ],
        // 3 · Ammersee West (~18 km)
        [
            .init(latitude: 48.0025, longitude: 11.1208),
            .init(latitude: 48.0080, longitude: 11.1168),
            .init(latitude: 48.0138, longitude: 11.1125),
            .init(latitude: 48.0198, longitude: 11.1085),
            .init(latitude: 48.0258, longitude: 11.1052),
            .init(latitude: 48.0318, longitude: 11.1028),
            .init(latitude: 48.0258, longitude: 11.1005),
            .init(latitude: 48.0198, longitude: 11.0975),
            .init(latitude: 48.0138, longitude: 11.0948),
            .init(latitude: 48.0080, longitude: 11.0978),
            .init(latitude: 48.0025, longitude: 11.1012),
            .init(latitude: 47.9968, longitude: 11.1050),
            .init(latitude: 48.0025, longitude: 11.1208),
        ],
    ]}

    // ── Wandern ──────────────────────────────────────────────────────────────

    private var hikingRoutes: [[CLLocationCoordinate2D]] { [
        // 1 · Herzogstand (840 m Höhenunterschied, ~7 km)
        [
            .init(latitude: 47.6255, longitude: 11.4408),
            .init(latitude: 47.6282, longitude: 11.4428),
            .init(latitude: 47.6312, longitude: 11.4445),
            .init(latitude: 47.6342, longitude: 11.4458),
            .init(latitude: 47.6372, longitude: 11.4468),
            .init(latitude: 47.6402, longitude: 11.4475),
            .init(latitude: 47.6432, longitude: 11.4480),
            .init(latitude: 47.6462, longitude: 11.4485),
            .init(latitude: 47.6492, longitude: 11.4488),
            .init(latitude: 47.6522, longitude: 11.4490),
            .init(latitude: 47.6548, longitude: 11.4492),
            .init(latitude: 47.6522, longitude: 11.4490),
            .init(latitude: 47.6492, longitude: 11.4488),
            .init(latitude: 47.6462, longitude: 11.4485),
            .init(latitude: 47.6432, longitude: 11.4480),
            .init(latitude: 47.6402, longitude: 11.4475),
            .init(latitude: 47.6372, longitude: 11.4468),
            .init(latitude: 47.6342, longitude: 11.4458),
            .init(latitude: 47.6312, longitude: 11.4445),
            .init(latitude: 47.6282, longitude: 11.4428),
            .init(latitude: 47.6255, longitude: 11.4408),
        ],
        // 2 · Schliersee Jägerkamp (~9 km)
        [
            .init(latitude: 47.7272, longitude: 11.8618),
            .init(latitude: 47.7305, longitude: 11.8648),
            .init(latitude: 47.7338, longitude: 11.8672),
            .init(latitude: 47.7372, longitude: 11.8690),
            .init(latitude: 47.7405, longitude: 11.8700),
            .init(latitude: 47.7438, longitude: 11.8705),
            .init(latitude: 47.7465, longitude: 11.8702),
            .init(latitude: 47.7438, longitude: 11.8705),
            .init(latitude: 47.7405, longitude: 11.8700),
            .init(latitude: 47.7372, longitude: 11.8690),
            .init(latitude: 47.7338, longitude: 11.8672),
            .init(latitude: 47.7305, longitude: 11.8648),
            .init(latitude: 47.7272, longitude: 11.8618),
        ],
        // 3 · Zugspitz-Plateau (~6 km)
        [
            .init(latitude: 47.4200, longitude: 10.9832),
            .init(latitude: 47.4228, longitude: 10.9858),
            .init(latitude: 47.4255, longitude: 10.9882),
            .init(latitude: 47.4282, longitude: 10.9905),
            .init(latitude: 47.4308, longitude: 10.9925),
            .init(latitude: 47.4332, longitude: 10.9940),
            .init(latitude: 47.4355, longitude: 10.9950),
            .init(latitude: 47.4332, longitude: 10.9940),
            .init(latitude: 47.4308, longitude: 10.9925),
            .init(latitude: 47.4282, longitude: 10.9905),
            .init(latitude: 47.4255, longitude: 10.9882),
            .init(latitude: 47.4228, longitude: 10.9858),
            .init(latitude: 47.4200, longitude: 10.9832),
        ],
    ]}
}
