import SwiftUI

struct ActiveWorkoutView: View {
    @Environment(LocationService.self)        private var location
    @Environment(HealthKitService.self)       private var healthKit
    @Environment(WatchConnectivityService.self) private var watch
    @Environment(NotificationService.self)    private var notifications
    @Environment(UserSettings.self)           private var settings
    @Environment(WorkoutDraftStore.self)      private var draftStore
    @Environment(\.scenePhase)                private var scenePhase

    @State private var selectedType:     WorkoutType = .running
    @State private var isActive          = false
    @State private var workoutStart:     Date?
    @State private var elapsed:          TimeInterval = 0
    @State private var timer:            Timer?
    @State private var previousDistance: Double = 0
    @State private var lastDraftSaveMark: Int = -1
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
                    AppChromeActionLabel(systemImage: "clock.arrow.circlepath", tint: .green)
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

        return [
            AppHeaderMetric(
                title: lt("Workout"),
                value: selectedType.displayName,
                systemImage: selectedType.systemImage,
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
            .accessibilityLabel(isMapExpanded ? "Karte verkleinern" : "Karte maximieren")
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
                ForEach(WorkoutType.allCases) { type in
                    Button { selectedType = type } label: {
                        VStack(spacing: 4) {
                            Image(systemName: type.systemImage).font(.title3)
                            Text(type.displayName).font(.caption2)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(selectedType == type ? Color.accentColor : Color.secondary.opacity(0.15))
                        .foregroundStyle(selectedType == type ? .white : .primary)
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal).padding(.vertical, 10)
        }
    }

    private var liveMetricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            LiveMetric(title: lt("Zeit"),     value: elapsed.formatted,             icon: "timer",       color: .primary)
            LiveMetric(title: lt("Distanz"),  value: settings.unitPreference.formatted(meters: location.totalDistanceMeters), icon: "map",         color: .blue)
            LiveMetric(title: lt("Tempo"),    value: speedLabel,                    icon: "speedometer", color: .purple)
            LiveMetric(title: lt("Schritte"), value: "--",                          icon: "figure.walk", color: .green)
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
        Button(action: isActive ? stopWorkout : startWorkout) {
            Text(isActive ? lt("Workout beenden") : lt("Workout starten"))
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(isActive ? Color.red : Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .padding()
    }

    private func draftRecoveryCard(_ draft: WorkoutDraft) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(draft.status == .pendingSave ? "Ungesichertes Workout gefunden" : "Laufendes Workout wiederherstellen")
                .font(.headline)
            Text(draftSummary(draft))
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(draft.status == .pendingSave ? "Workout jetzt sichern" : "Workout fortsetzen") {
                switch draft.status {
                case .active:
                    restoreDraft(draft)
                case .pendingSave:
                    Task { await saveRecoveredDraft(draft) }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSavingRecoveredDraft)

            Button("Entwurf verwerfen", role: .destructive) {
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
        location.requestAuthorization()
        location.startTracking()
        workoutStart    = Date()
        elapsed         = 0
        previousDistance = 0
        lastDraftSaveMark = -1
        isActive        = true
        persistCurrentDraft(status: .active)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            elapsed += 1
            checkMilestone()
            autosaveIfNeeded()
        }
    }

    private func stopWorkout() {
        let route = location.stopTracking()
        timer?.invalidate(); timer = nil
        isActive = false

        guard let start = workoutStart else { return }
        let end      = Date()
        let distance = location.totalDistanceMeters
        persistCurrentDraft(status: .pendingSave, route: route, distanceMeters: distance, endDate: end)

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
        draftStore.save(
            WorkoutDraft(
                id: draft.id,
                workoutType: draft.workoutType,
                startDate: draft.startDate,
                lastUpdated: Date(),
                distanceMeters: draft.distanceMeters,
                route: draft.route,
                status: .active
            )
        )
        selectedType = draft.workoutType
        workoutStart = draft.startDate
        elapsed = max(0, Date().timeIntervalSince(draft.startDate))
        previousDistance = draft.distanceMeters
        lastDraftSaveMark = -1
        location.requestAuthorization()
        location.startTracking(route: draft.route, totalDistanceMeters: draft.distanceMeters)
        isActive = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            elapsed += 1
            checkMilestone()
            autosaveIfNeeded()
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
            status: status
        )
        draftStore.save(draft)
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
            routePoints: route
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
            elapsed = 0
        } catch {
            print("[WorkoutDraft] recovered save failed: \(error.localizedDescription)")
        }
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
