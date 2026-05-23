import SwiftUI

struct ActiveWorkoutView: View {
    @Environment(LocationService.self)        private var location
    @Environment(HealthKitService.self)       private var healthKit
    @Environment(WatchConnectivityService.self) private var watch
    @Environment(NotificationService.self)    private var notifications
    @Environment(UserSettings.self)           private var settings
    @Environment(WorkoutDraftStore.self)      private var draftStore
    @Environment(FoodLogStore.self)           private var foodLog
    @Environment(\.scenePhase)                private var scenePhase

    private let workoutSurface = WorkoutSurfaceService.shared

    @State private var favoriteStore    = WorkoutFavoriteStore.shared
    @State private var customSportStore = CustomSportStore.shared
    @State private var usageStore       = WorkoutUsageStore.shared
    @State private var selectedType:     WorkoutType = .running
    @State private var selectedCustomSport: CustomSport? = nil
    @State private var showAddCustomSport = false
    @State private var isActive          = false
    @State private var isPaused          = false
    /// Akkumulierte Pause-Dauer in Sekunden — bei jedem Resume um die Dauer
    /// der letzten Pause erhöht.
    @State private var accumulatedPause:  TimeInterval = 0
    /// Zeitpunkt zu dem die aktuelle Pause begann.
    @State private var pauseStart:        Date?
    @State private var workoutStart:     Date?
    @State private var elapsed:          TimeInterval = 0
    @State private var timer:            Timer?
    @State private var previousDistance: Double = 0
    @State private var lastDraftSaveMark: Int = -1
    @State private var lastSurfaceUpdateMark: Int = -1
    @State private var isSavingRecoveredDraft = false
    @State private var isMapExpanded = false

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                if geo.size.width > geo.size.height {
                    HStack(spacing: 0) {
                        mapLayer
                        metricsLayer.frame(width: isMapExpanded ? 220 : 300)
                    }
                } else {
                    VStack(spacing: 0) {
                        mapLayer.frame(height: portraitMapHeight(for: geo.size))
                        metricsLayer
                    }
                }
            }
            .appChrome(title: lt("Workout"), accent: .green, metrics: headerMetrics) {
                NavigationLink {
                    WorkoutHistoryView()
                } label: {
                    AppChromeActionLabel(systemImage: "clock.arrow.circlepath", tint: .green, style: .prominent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(lt("Workout-Verlauf"))
            }
        }
    }

    private var headerMetrics: [AppHeaderMetric] {
        if isActive {
            return [
                AppHeaderMetric(
                    title: lt("Zeit"),
                    value: elapsed.formatted,
                    systemImage: "timer",
                    tint: .primary
                ),
                AppHeaderMetric(
                    title: lt("Tempo"),
                    value: speedLabel,
                    systemImage: "speedometer",
                    tint: .purple
                )
            ]
        }

        let currentName = selectedCustomSport?.name ?? selectedType.displayName
        let currentImage = selectedCustomSport.map { $0.symbol } ?? selectedType.systemImage
        return [
            AppHeaderMetric(
                title: lt("Workout"),
                value: currentName,
                systemImage: currentImage,
                tint: .green
            ),
            AppHeaderMetric(
                title: lt("Distanz"),
                value: settings.unitPreference.formatted(meters: location.totalDistanceMeters),
                systemImage: "map",
                tint: .blue
            )
        ]
    }

    // MARK: - Subviews

    private var mapLayer: some View {
        RouteMapView(
            routePoints: location.recordedRoute,
            currentLocation: location.currentLocation
        )
        .overlay(alignment: .bottomTrailing) {
            Button {
                withAnimation(.spring(duration: 0.28)) {
                    isMapExpanded.toggle()
                }
            } label: {
                Image(systemName: isMapExpanded
                      ? "arrow.down.right.and.arrow.up.left"
                      : "arrow.up.left.and.arrow.down.right")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 42, height: 42)
                    .background(.thinMaterial, in: Circle())
                    .overlay {
                        Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .padding(12)
            .accessibilityLabel(isMapExpanded ? lt("Karte verkleinern") : lt("Karte maximieren"))
        }
    }

    private var metricsLayer: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if !isActive {
                        workoutTypePicker
                    }
                    if !isActive, let draft = draftStore.currentDraft {
                        draftRecoveryCard(draft)
                    }
                    liveMetricsGrid
                    if watch.isWorkoutActiveOnWatch { watchBadge }
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.bottom, 8)
            }
            .scrollBounceBehavior(.basedOnSize)

            startStopButton
        }
        .background(.background)
        .onChange(of: scenePhase) { _, newPhase in
            guard isActive, newPhase != .active else { return }
            persistCurrentDraft(status: .active)
            refreshWorkoutSurface(force: true)
        }
        .task {
            restoreDraftPreviewIfNeeded()
        }
    }

    private func portraitMapHeight(for size: CGSize) -> CGFloat {
        let collapsed = size.height * 0.42
        let expanded = size.height * 0.68
        return isMapExpanded ? expanded : collapsed
    }

    private var workoutTypePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                // Favoriten (built-in) zuerst — Favoriten untereinander nach Häufigkeit sortiert
                let favTypes = usageStore.sortedByUsage(WorkoutType.allCases.filter { favoriteStore.isFavorite($0) })
                if !favTypes.isEmpty {
                    ForEach(favTypes) { type in
                        builtInTypeChip(type)
                    }
                    Divider().frame(height: 40)
                }

                // Benutzerdefinierte Sportarten
                ForEach(customSportStore.sports) { sport in
                    Button {
                        selectedCustomSport = sport
                        selectedType = .other
                    } label: {
                        VStack(spacing: 4) {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: sport.symbol).font(.title3)
                                Image(systemName: "star.fill")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.yellow)
                                    .offset(x: 6, y: -4)
                            }
                            Text(sport.name).font(.caption2).lineLimit(1)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(selectedCustomSport?.id == sport.id ? Color.accentColor : Color.secondary.opacity(0.15))
                        .foregroundStyle(selectedCustomSport?.id == sport.id ? .white : .primary)
                        .clipShape(Capsule())
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            if selectedCustomSport?.id == sport.id { selectedCustomSport = nil }
                            customSportStore.remove(sport)
                        } label: {
                            Label(lt("Entfernen"), systemImage: "trash")
                        }
                    }
                }

                // Alle Standard-Typen (Favoriten ohne Duplikat) — sortiert nach Häufigkeit der Nutzung
                let nonFavTypes = usageStore.sortedByUsage(WorkoutType.allCases.filter { !favoriteStore.isFavorite($0) })
                ForEach(nonFavTypes) { type in
                    builtInTypeChip(type)
                }

                // '+' zum Hinzufügen einer eigenen Sportart
                Button { showAddCustomSport = true } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill").font(.title3)
                        Text(lt("Eigene")).font(.caption2)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(Capsule())
                }
            }
            .padding(.horizontal).padding(.vertical, 10)
        }
        .sheet(isPresented: $showAddCustomSport) {
            AddCustomSportSheet(store: customSportStore)
        }
    }

    private func builtInTypeChip(_ type: WorkoutType) -> some View {
        let isSelected = selectedCustomSport == nil && selectedType == type
        // Leichte Aktivitäten (Gehen, E-Bike, Gartenarbeit) bekommen
        // einen Teal-Akzent, damit man auf einen Blick sieht: das ist
        // entspannte Bewegung, kein Workout im klassischen Sinn.
        let isLight = type.category == .light
        let accent: Color = isLight ? .teal : Color.accentColor
        let bgUnselected: Color = isLight ? Color.teal.opacity(0.12) : Color.secondary.opacity(0.15)
        let fgUnselected: Color = isLight ? .teal : .primary

        return Button {
            selectedType = type
            selectedCustomSport = nil
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: type.systemImage).font(.title3)
                    if favoriteStore.isFavorite(type) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.yellow)
                            .offset(x: 6, y: -4)
                    }
                }
                Text(type.displayName).font(.caption2)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(isSelected ? accent : bgUnselected)
            .foregroundStyle(isSelected ? Color.white : fgUnselected)
            .clipShape(Capsule())
        }
        .contextMenu {
            Button {
                favoriteStore.toggle(type)
            } label: {
                Label(
                    favoriteStore.isFavorite(type) ? lt("Aus Favoriten") : lt("Als Favorit"),
                    systemImage: favoriteStore.isFavorite(type) ? "star.slash" : "star"
                )
            }
        }
    }

    private var liveMetricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            LiveMetric(title: lt("Zeit"),         value: elapsed.formatted,             icon: "timer",          color: .primary)
            LiveMetric(title: lt("Distanz"),      value: settings.unitPreference.formatted(meters: location.totalDistanceMeters), icon: "map", color: .blue)
            LiveMetric(title: lt("Tempo"),        value: speedLabel,                    icon: "speedometer",    color: .purple)
            LiveMetric(title: lt("Schritte"),     value: "--",                          icon: "figure.walk",    color: .green)
            LiveMetric(title: lt("Höhe"),         value: altitudeLabel,                 icon: "mountain.2",     color: .orange)
            LiveMetric(title: lt("Höhengewinn"),  value: elevationGainLabel,            icon: "arrow.up.right", color: .teal)
        }
        .padding()
    }

    private var watchBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "applewatch").font(.caption)
            Text(lf("Watch: %d bpm · %d kcal", Int(watch.liveMetrics.heartRate), Int(watch.liveMetrics.activeCalories)))
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal)
    }

    private var startStopButton: some View {
        VStack(spacing: 10) {
            if isPaused {
                // Pause-Indikator über den Buttons
                HStack(spacing: 6) {
                    Image(systemName: "pause.circle.fill")
                        .foregroundStyle(.orange)
                    Text(lt("Pausiert"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                .padding(.bottom, 2)
            }

            if isActive {
                HStack(spacing: 10) {
                    // Pause/Resume — links, sekundär
                    Button(action: togglePause) {
                        HStack(spacing: 6) {
                            Image(systemName: isPaused ? "play.fill" : "pause.fill")
                            Text(isPaused ? lt("Fortsetzen") : lt("Pause"))
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isPaused ? Color.green : Color.orange)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    // Stop — rechts, destruktiv
                    Button(action: stopWorkout) {
                        HStack(spacing: 6) {
                            Image(systemName: "stop.fill")
                            Text(lt("Beenden"))
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                }
            } else {
                Button(action: startWorkout) {
                    Text(lt("Workout starten"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
        }
        .padding()
    }

    /// Pause toggle: misst die aktuelle Pause-Dauer und addiert sie zu
    /// `accumulatedPause`, sodass `elapsed` weiterhin die echte Aktivzeit zeigt.
    private func togglePause() {
        if isPaused {
            // Resume
            if let started = pauseStart {
                accumulatedPause += Date().timeIntervalSince(started)
            }
            pauseStart = nil
            isPaused = false
            location.resumeTracking()
        } else {
            // Pause
            pauseStart = Date()
            isPaused = true
            location.pauseTracking()
        }
        persistCurrentDraft(status: .active)
        refreshWorkoutSurface()
    }

    private func draftRecoveryCard(_ draft: WorkoutDraft) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(draft.status == .pendingSave ? lt("Ungesichertes Workout gefunden") : lt("Laufendes Workout wiederherstellen"))
                .font(.headline)
            Text(draftSummary(draft))
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(draft.status == .pendingSave ? lt("Workout jetzt sichern") : lt("Workout fortsetzen")) {
                switch draft.status {
                case .active:
                    restoreDraft(draft)
                case .pendingSave:
                    Task { await saveRecoveredDraft(draft) }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSavingRecoveredDraft)

            Button(lt("Entwurf verwerfen"), role: .destructive) {
                draftStore.clear()
            }
            .buttonStyle(.bordered)
            .disabled(isSavingRecoveredDraft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - Helpers

    private var speedLabel: String {
        guard location.currentSpeedMPS > 0 else { return "--" }
        switch settings.unitPreference {
        case .metric:
            let secPerKm = 1_000 / location.currentSpeedMPS
            return String(format: "%d:%02d /km", Int(secPerKm) / 60, Int(secPerKm) % 60)
        case .imperial:
            let secPerMi = 1_609.344 / location.currentSpeedMPS
            return String(format: "%d:%02d /mi", Int(secPerMi) / 60, Int(secPerMi) % 60)
        }
    }

    private var altitudeLabel: String {
        let m = location.currentAltitudeMeters
        switch settings.unitPreference {
        case .metric:   return String(format: "%.0f m", m)
        case .imperial: return String(format: "%.0f ft", m * 3.28084)
        }
    }

    private var elevationGainLabel: String {
        let m = location.totalElevationGainMeters
        switch settings.unitPreference {
        case .metric:   return String(format: "%.0f m", m)
        case .imperial: return String(format: "%.0f ft", m * 3.28084)
        }
    }

    private var selectedWorkoutName: String {
        selectedCustomSport?.name ?? selectedType.displayName
    }

    private var selectedWorkoutSymbol: String {
        selectedCustomSport?.symbol ?? selectedType.systemImage
    }

    private var trackingDistanceUnit: TrackingDistanceUnit {
        TrackingDistanceUnit(rawValue: settings.unitPreference.rawValue) ?? .metric
    }

    private func draftSummary(_ draft: WorkoutDraft) -> String {
        let end = draft.endDate ?? draft.lastUpdated
        let duration = max(0, end.timeIntervalSince(draft.startDate))
        return [
            draft.workoutType.displayName,
            duration.formatted,
            settings.unitPreference.formatted(meters: draft.distanceMeters)
        ].joined(separator: " • ")
    }

    // MARK: - Workout Control

    private func startWorkout() {
        draftStore.clear()
        // Nutzung zählen — sortiert den Picker beim nächsten Mal entsprechend
        usageStore.recordUsage(of: selectedType)
        location.requestAuthorization()
        location.startTracking()
        let start        = Date()
        workoutStart    = start
        elapsed         = 0
        previousDistance = 0
        lastDraftSaveMark = -1
        lastSurfaceUpdateMark = -1
        isActive        = true
        isPaused        = false
        accumulatedPause = 0
        pauseStart       = nil
        persistCurrentDraft(status: .active)
        workoutSurface.startWorkout(
            workoutName: selectedWorkoutName,
            systemImageName: selectedWorkoutSymbol,
            startDate: start,
            distanceMeters: location.totalDistanceMeters,
            speedMetersPerSecond: location.currentSpeedMPS,
            unit: trackingDistanceUnit
        )
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            // Bei PAUSE: kein Timer-Inkrement, kein Milestone-Check, kein Autosave
            guard !isPaused else {
                refreshWorkoutSurface()
                return
            }
            elapsed += 1
            checkMilestone()
            autosaveIfNeeded()
            refreshWorkoutSurface()
        }
    }

    private func stopWorkout() {
        let workoutName = selectedWorkoutName
        let workoutSymbol = selectedWorkoutSymbol
        let unit = trackingDistanceUnit
        // Falls noch in Pause: aktuelle Pause-Dauer für korrekte elapsed-Zeit
        // im finalen HK-Workout einrechnen.
        if isPaused, let pStart = pauseStart {
            accumulatedPause += Date().timeIntervalSince(pStart)
        }
        let route = location.stopTracking()
        timer?.invalidate(); timer = nil
        isActive = false
        isPaused = false
        pauseStart = nil

        guard let start = workoutStart else { return }
        let end      = Date()
        let distance = location.totalDistanceMeters
        persistCurrentDraft(status: .pendingSave, route: route, distanceMeters: distance, endDate: end)
        workoutSurface.finishWorkout(
            workoutName: workoutName,
            systemImageName: workoutSymbol,
            startDate: start,
            endDate: end,
            distanceMeters: distance,
            unit: unit
        )

        Task {
            do {
                try await saveWorkoutToHealth(
                    type: selectedType,
                    start: start,
                    end: end,
                    distanceMeters: distance,
                    route: route
                )
                draftStore.clear()
                await healthKit.refreshTodayData()
                await healthKit.loadWorkouts()
                await MainActor.run {
                    refreshStatisticsSurface()
                }
            } catch {
                print("[WorkoutDraft] save on stop failed: \(error.localizedDescription)")
            }
        }
        workoutStart = nil; elapsed = 0
    }

    private func restoreDraftPreviewIfNeeded() {
        guard !isActive, let draft = draftStore.currentDraft else { return }
        selectedType = draft.workoutType
        if draft.status == .pendingSave {
            elapsed = max(0, (draft.endDate ?? draft.lastUpdated).timeIntervalSince(draft.startDate))
        }
    }

    private func restoreDraft(_ draft: WorkoutDraft) {
        // Pause-State aus Draft wiederherstellen (Achtung: wenn die App während
        // der Pause beendet wurde, läuft die Pause-Dauer währenddessen weiter).
        let priorPauseSeconds = draft.pausedSeconds ?? 0
        let restorePaused = draft.isPaused == true
        var totalPause = priorPauseSeconds
        if restorePaused, let pStart = draft.pauseStartedAt {
            // Pause läuft noch — Zeit bis jetzt mitzählen für korrektes elapsed
            totalPause += Date().timeIntervalSince(pStart)
        }

        draftStore.save(
            WorkoutDraft(
                id: draft.id,
                workoutType: draft.workoutType,
                startDate: draft.startDate,
                lastUpdated: Date(),
                distanceMeters: draft.distanceMeters,
                route: draft.route,
                status: .active,
                pausedSeconds: priorPauseSeconds,
                isPaused: restorePaused ? true : nil,
                pauseStartedAt: draft.pauseStartedAt
            )
        )
        selectedType = draft.workoutType
        workoutStart = draft.startDate
        // elapsed = (now - start) - totalPause → echte Aktivzeit
        elapsed = max(0, Date().timeIntervalSince(draft.startDate) - totalPause)
        accumulatedPause = priorPauseSeconds
        isPaused = restorePaused
        pauseStart = restorePaused ? draft.pauseStartedAt : nil
        previousDistance = draft.distanceMeters
        lastDraftSaveMark = -1
        lastSurfaceUpdateMark = -1
        location.requestAuthorization()
        location.startTracking(route: draft.route, totalDistanceMeters: draft.distanceMeters)
        if restorePaused { location.pauseTracking() }
        isActive = true
        timer?.invalidate()
        workoutSurface.startWorkout(
            workoutName: selectedWorkoutName,
            systemImageName: selectedWorkoutSymbol,
            startDate: draft.startDate,
            distanceMeters: draft.distanceMeters,
            speedMetersPerSecond: location.currentSpeedMPS,
            unit: trackingDistanceUnit
        )
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            guard !isPaused else {
                refreshWorkoutSurface()
                return
            }
            elapsed += 1
            checkMilestone()
            autosaveIfNeeded()
            refreshWorkoutSurface()
        }
    }

    private func autosaveIfNeeded() {
        let mark = Int(elapsed)
        guard isActive, mark > 0, mark.isMultiple(of: 10), mark != lastDraftSaveMark else { return }
        lastDraftSaveMark = mark
        persistCurrentDraft(status: .active)
    }

    private func persistCurrentDraft(
        status: WorkoutDraftStatus,
        route: [RoutePoint]? = nil,
        distanceMeters: Double? = nil,
        endDate: Date? = nil
    ) {
        guard let start = workoutStart else { return }
        let draft = WorkoutDraft(
            workoutType: selectedType,
            startDate: start,
            endDate: endDate,
            lastUpdated: Date(),
            distanceMeters: distanceMeters ?? location.totalDistanceMeters,
            route: route ?? location.recordedRoute,
            status: status,
            pausedSeconds: accumulatedPause > 0 ? accumulatedPause : nil,
            isPaused: isPaused ? true : nil,
            pauseStartedAt: pauseStart
        )
        draftStore.save(draft)
    }

    private func refreshWorkoutSurface(force: Bool = false) {
        guard isActive, let start = workoutStart else { return }
        let mark = Int(elapsed)
        guard force || (mark > 0 && mark.isMultiple(of: 15) && mark != lastSurfaceUpdateMark) else { return }
        lastSurfaceUpdateMark = mark
        workoutSurface.updateWorkout(
            workoutName: selectedWorkoutName,
            systemImageName: selectedWorkoutSymbol,
            startDate: start,
            distanceMeters: location.totalDistanceMeters,
            speedMetersPerSecond: location.currentSpeedMPS,
            unit: trackingDistanceUnit
        )
    }

    private func saveWorkoutToHealth(
        type: WorkoutType,
        start: Date,
        end: Date,
        distanceMeters: Double,
        route: [RoutePoint]
    ) async throws {
        let duration = end.timeIntervalSince(start)
        let profile  = healthKit.profileSnapshot(settings: settings)
        let calories = CaloricEstimator.estimate(
            type: type,
            distanceMeters: distanceMeters,
            durationSec: duration,
            profile: profile
        )
        try await healthKit.saveWorkout(
            type: type,
            start: start,
            end: end,
            steps: 0,
            calories: calories,
            distanceMeters: distanceMeters,
            routePoints: route,
            customName: selectedCustomSport?.name
        )
    }

    private func saveRecoveredDraft(_ draft: WorkoutDraft) async {
        guard draft.status == .pendingSave, let end = draft.endDate else { return }
        isSavingRecoveredDraft = true
        defer { isSavingRecoveredDraft = false }

        do {
            try await saveWorkoutToHealth(
                type: draft.workoutType,
                start: draft.startDate,
                end: end,
                distanceMeters: draft.distanceMeters,
                route: draft.route
            )
            draftStore.clear()
            await healthKit.refreshTodayData()
            await healthKit.loadWorkouts()
            refreshStatisticsSurface()
            elapsed = 0
        } catch {
            print("[WorkoutDraft] recovered save failed: \(error.localizedDescription)")
        }
    }

    private func refreshStatisticsSurface() {
        workoutSurface.updateStatistics(
            healthKit: healthKit,
            settings: settings,
            foodLog: foodLog
        )
    }

    private func checkMilestone() {
        let current = location.totalDistanceMeters
        notifications.checkMilestone(
            previousMeters: previousDistance,
            currentMeters:  current,
            unit:           settings.unitPreference,
            workoutType:    selectedType,
            speedMPS:       location.currentSpeedMPS
        )
        previousDistance = current
    }

}

// MARK: - AddCustomSportSheet

private struct AddCustomSportSheet: View {
    @Environment(\.dismiss) private var dismiss
    let store: CustomSportStore

    @State private var name = ""
    @State private var symbol = "figure.mixed.cardio"

    var body: some View {
        NavigationStack {
            Form {
                Section(lt("Name der Sportart")) {
                    TextField(lt("z. B. Bouldern, Crossfit, Kickboxen"), text: $name)
                        .textInputAutocapitalization(.sentences)
                }
                Section(lt("Symbol")) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 6) {
                        ForEach(CustomSportStore.symbolChoices, id: \.self) { s in
                            Image(systemName: s)
                                .font(.title3)
                                .foregroundStyle(s == symbol ? Color.accentColor : .secondary)
                                .frame(width: 44, height: 44)
                                .background(s == symbol ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .onTapGesture { symbol = s }
                        }
                    }
                }
            }
            .navigationTitle(lt("Sportart hinzufügen"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(lt("Abbrechen")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(lt("Hinzufügen")) {
                        store.add(name: name, symbol: symbol)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - LiveMetric tile

struct LiveMetric: View {
    let title: String
    let value: String
    let icon:  String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold()).minimumScaleFactor(0.6).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
