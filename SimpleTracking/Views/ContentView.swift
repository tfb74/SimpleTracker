import SwiftUI

private enum AppTab: Hashable {
    case dashboard
    case workout
    case nutrition
    case statistics
    case settings
}

struct ContentView: View {
    @Environment(HealthKitService.self) private var healthKit
    @Environment(WatchConnectivityService.self) private var watch
    @Environment(NotificationService.self) private var notifications
    @Environment(AdService.self) private var ads
    @Environment(\.scenePhase) private var scenePhase

    @State private var autoShowDetail: WorkoutRecord?
    @State private var selectedTab: AppTab = .dashboard

    var body: some View {
        @Bindable var ads = ads

        TabView(selection: $selectedTab) {
            DashboardView()
                .tabItem { Label(lt("Heute"), systemImage: "house.fill") }
                .tag(AppTab.dashboard)

            ActiveWorkoutView()
                .tabItem { Label(lt("Workout"), systemImage: "figure.run") }
                .tag(AppTab.workout)

            FoodLogView()
                .tabItem { Label(lt("Ernährung"), systemImage: "fork.knife") }
                .tag(AppTab.nutrition)

            StatisticsView()
                .tabItem { Label(lt("Statistiken"), systemImage: "chart.line.uptrend.xyaxis") }
                .tag(AppTab.statistics)

            SettingsView()
                .tabItem { Label(lt("Mehr"), systemImage: "gearshape.fill") }
                .tag(AppTab.settings)
        }
        .fullScreenCover(item: $autoShowDetail) { workout in
            NavigationStack {
                WorkoutDetailView(workout: workout)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(lt("Schließen")) { autoShowDetail = nil }
                        }
                    }
            }
        }
        .sheet(item: $ads.weeklyInterstitialPrompt) { prompt in
            WeeklyInterstitialPromptSheet(
                prompt: prompt,
                onSkip: { ads.skipWeeklyInterstitialPrompt() },
                onContinue: { ads.confirmWeeklyInterstitialPrompt() }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $ads.debugInterstitialPreviewPresented) {
            DebugInterstitialPreviewView {
                ads.dismissDebugInterstitialPreview()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await healthKit.refreshTodayData()
                await healthKit.loadWorkouts()
            }
            if selectedTab == .statistics && autoShowDetail == nil {
                ads.considerWeeklyInterstitialOffer()
            }
        }
        .onChange(of: watch.isWorkoutActiveOnWatch) { oldValue, newValue in
            guard oldValue, !newValue else { return }
            Task {
                await healthKit.refreshTodayData()
                await healthKit.loadWorkouts()
            }
        }
        .onChange(of: selectedTab) { _, newValue in
            guard newValue == .statistics, autoShowDetail == nil else { return }
            ads.considerWeeklyInterstitialOffer()
        }
        .task {
            try? await healthKit.requestAuthorization()
            await notifications.requestAuthorization()

            if ProcessInfo.processInfo.arguments.contains("-previewRoute") {
                autoShowDetail = MockDataService.shared.buildPreviewRecord()
            } else if ProcessInfo.processInfo.arguments.contains("-generateOne") {
                let mock = MockDataService.shared
                await mock.deleteAll()
                await mock.generateOne()
                await healthKit.importAllWorkouts()
                autoShowDetail = healthKit.workouts.first
            }
        }
    }
}

private struct WeeklyInterstitialPromptSheet: View {
    let prompt: AdService.WeeklyInterstitialPrompt
    let onSkip: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Gesponsert", systemImage: "megaphone.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Gesponserter Hinweis")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)

                Text(descriptionText)
                    .font(.body)
                    .foregroundStyle(.secondary)

                Text("Diese Anzeige unterstützt die Weiterentwicklung von SimpleTracking.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                Button(action: onContinue) {
                    Text("Jetzt ansehen")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                if prompt.canSkip {
                    Button(action: onSkip) {
                        Text("Später")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(24)
    }

    private var descriptionText: String {
        if prompt.canSkip {
            return "Einmal pro Woche zeigen wir dir einen gesponserten Vollbild-Hinweis. Du kannst ihn diese Woche noch \(prompt.skipsRemaining)x überspringen."
        }
        return "Diese Wochenanzeige ist jetzt fällig. Nach dem Schließen bleibt für diese Woche wieder Ruhe."
    }
}

private struct DebugInterstitialPreviewView: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.orange.opacity(0.95), Color.red.opacity(0.9)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                VStack(alignment: .leading, spacing: 14) {
                    Text("Gesponsert")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))

                    Text("Fullscreen-Ad Vorschau")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.white)

                    Text("Im Simulator erzwingen wir hier eine sichtbare Vorschau, damit du die Wochenlogik sauber testen kannst.")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.92))
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 28))
                .padding(.horizontal, 24)

                Spacer()

                Button(action: onDismiss) {
                    Text("Anzeige schließen")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
                .padding(.horizontal, 24)
                .padding(.bottom, 36)
            }
        }
    }
}
