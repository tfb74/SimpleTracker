import SwiftUI
import UIKit
import CoreLocation

struct DashboardView: View {
    @Environment(HealthKitService.self) private var healthKit
    @Environment(UserSettings.self)    private var settings
    @Environment(FoodLogStore.self)    private var foodLog

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    todayGrid
                    energyBalanceCard
                    recentWorkouts
                }
                .padding(.vertical)
            }
            .appChrome(title: lt("Heute"), accent: .blue, metrics: headerMetrics) {
                NavigationLink {
                    WorkoutGuideView()
                } label: {
                    AppChromeActionLabel(systemImage: "info.circle", tint: .blue)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(lt("Tracking-Hilfe"))
            }
            .refreshable { await healthKit.refreshTodayData() }
        }
    }

    private var headerMetrics: [AppHeaderMetric] {
        let bestScore = healthKit.workouts.map { $0.score(settings: settings).displayScore }.max()

        return [
            AppHeaderMetric(
                title: lt("Schritte"),
                value: healthKit.todaySteps.formatted(),
                systemImage: "figure.walk",
                tint: .blue
            ),
            AppHeaderMetric(
                title: "Bester Score",
                value: bestScore.map(String.init) ?? "--",
                systemImage: "star.fill",
                tint: .yellow
            )
        ]
    }

    private var todayGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            MetricCard(
                title: lt("Schritte"),
                value: healthKit.todaySteps.formatted(),
                unit: lt("Schritte"),
                icon: "figure.walk",
                color: .blue
            )
            MetricCard(
                title: lt("Kalorien"),
                value: String(format: "%.0f", healthKit.todayCalories),
                unit: "kcal",
                icon: "flame.fill",
                color: .orange
            )
            MetricCard(
                title: lt("Distanz"),
                value: settings.unitPreference == .metric
                    ? String(format: "%.2f", healthKit.todayDistanceKm)
                    : String(format: "%.2f", healthKit.todayDistanceKm / 1.60934),
                unit: settings.unitPreference.distanceLabel,
                icon: "map.fill",
                color: .green
            )
        }
        .padding(.horizontal)
    }

    private var energyBalanceCard: some View {
        let burned   = healthKit.todayCalories
        let food     = foodLog.totals(on: Date())
        let consumed = food.kcal
        let balance  = consumed - burned
        let positive = balance > 0
        let ratio    = burned > 0 ? min(consumed / max(burned, 1), 2.0) : 0

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(lt("Energie-Bilanz heute"), systemImage: "arrow.left.arrow.right.circle.fill")
                    .font(.headline)
                Spacer()
                Text(positive ? "+\(Int(balance)) kcal" : "\(Int(balance)) kcal")
                    .font(.headline.bold())
                    .foregroundStyle(positive ? .red : .green)
            }

            HStack(spacing: 10) {
                balanceTile(title: lt("Verbraucht"), value: burned,   color: .orange, icon: "flame.fill")
                balanceTile(title: lt("Aufgenommen"), value: consumed, color: .red,    icon: "fork.knife")
                balanceTile(title: "BE",          value: food.be,  color: .purple, icon: "square.grid.2x2.fill", isBE: true)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule()
                        .fill(positive ? Color.red.gradient : Color.green.gradient)
                        .frame(width: geo.size.width * CGFloat(ratio / 2.0))
                }
            }
            .frame(height: 6)

            Text(positive
                 ? lt("Du hast heute mehr gegessen als verbraucht.")
                 : burned > 0
                   ? lt("Du bist im Defizit – mehr verbraucht als gegessen.")
                   : lt("Noch keine Aktivität gemessen."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private func balanceTile(title: String, value: Double, color: Color, icon: String, isBE: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon).font(.caption2).foregroundStyle(color)
            Text(isBE ? String(format: "%.1f", value) : String(format: "%.0f", value))
                .font(.title3.bold())
            Text(isBE ? "BE" : "kcal").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var recentWorkouts: some View {
        Group {
            if !healthKit.workouts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(lt("Letzte Workouts"))
                        .font(.headline)
                        .padding(.horizontal)

                    ForEach(healthKit.workouts.prefix(3)) { workout in
                        NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                            WorkoutRowView(workout: workout)
                                .padding(.horizontal)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

// MARK: - Reusable Components

struct MetricCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon).foregroundStyle(color)
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            Text(value).font(.title2.bold())
            Text(unit).font(.caption2).foregroundStyle(.secondary)
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct WorkoutRowView: View {
    let workout: WorkoutRecord
    @Environment(UserSettings.self) private var settings

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: workout.workoutType.systemImage)
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(workout.workoutType.displayName).font(.subheadline.bold())
                Text(workout.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(workout.formattedDistance(unit: settings.unitPreference))
                    .font(.subheadline.bold())
                Text(workout.duration.formatted)
                    .font(.caption).foregroundStyle(.secondary)
                ScorePill(score: workout.score(settings: settings))
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

extension TimeInterval {
    var formatted: String {
        let h = Int(self) / 3_600
        let m = (Int(self) % 3_600) / 60
        let s = Int(self) % 60
        return h > 0 ? lf("%d:%02d:%02d h", h, m, s) : lf("%d:%02d min", m, s)
    }
}

private struct WorkoutGuideView: View {
    @Environment(HealthKitService.self) private var healthKit
    @Environment(LocationService.self) private var location

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                guideCard(title: lt("Apple Watch vorbereiten"), icon: "applewatch") {
                    guideList([
                        lt("1. Öffne SimpleTracking auf der Apple Watch und bestätige die Health-Berechtigungen für Workouts, Herzfrequenz, Energie und Distanz."),
                        lt("2. Starte auf der Watch ein Outdoor-Workout und bleibe währenddessen möglichst unter freiem Himmel, damit GPS sauber erfasst werden kann."),
                        lt("3. Beende das Workout erst auf der Watch und öffne danach die iPhone-App wieder; SimpleTracking lädt Watch-Workouts beim Zurückkehren nun automatisch nach."),
                        lt("4. Für bessere Distanz- und Pace-Werte: iPhone Einstellungen > Datenschutz & Sicherheit > Ortungsdienste > Systemdienste > Bewegungs-kalibrierung & Distanz aktivieren und die Watch gelegentlich bei einem Outdoor Walk/Run kalibrieren.")
                    ])
                }

                guideCard(title: lt("Was auf dem iPhone aktiviert sein sollte"), icon: "iphone") {
                    Text(lt("SimpleTracking benötigt für sauberes Hintergrund-Tracking Standort auf „Immer“, „Genaue Position“ und möglichst aktivierte App-Aktualisierung im Hintergrund. Bitte die App während eines laufenden Workouts nicht aus dem app switcher wegwischen."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 10) {
                        statusRow(
                            title: lt("Standortzugriff"),
                            value: locationStatusLabel,
                            isGood: location.authorizationStatus == .authorizedAlways
                        )
                        statusRow(
                            title: lt("Präzise Ortung"),
                            value: accuracyLabel,
                            isGood: location.accuracyAuthorization == .fullAccuracy
                        )
                        statusRow(
                            title: lt("Background App Refresh"),
                            value: backgroundRefreshLabel,
                            isGood: UIApplication.shared.backgroundRefreshStatus == .available
                        )
                        statusRow(
                            title: lt("Health-Zugriff"),
                            value: healthKit.isAuthorized ? lt("Aktiv") : lt("Nicht aktiv"),
                            isGood: healthKit.isAuthorized
                        )
                    }

                    HStack(spacing: 12) {
                        Button(lt("Berechtigungen aktualisieren")) {
                            location.requestAuthorization()
                            Task { try? await healthKit.requestAuthorization() }
                        }
                        .buttonStyle(.borderedProminent)

                        Button(lt("iPhone-Einstellungen öffnen")) {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }

                guideCard(title: lt("Wichtiger Hinweis"), icon: "exclamationmark.triangle.fill") {
                    Text(lt("Die Watch liefert Live-Puls, Kalorien und Workout-Zeit an das iPhone. Die sichtbare GPS-Route in SimpleTracking zeichnet aktuell das iPhone auf. Wenn du die Route direkt in der App sehen willst, starte das Workout auf dem iPhone oder importiere das Watch-Workout danach aus Apple Health."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle(lt("Tracking-Hilfe"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var locationStatusLabel: String {
        switch location.authorizationStatus {
        case .authorizedAlways:
            return lt("Immer erlaubt")
        case .authorizedWhenInUse:
            return lt("Nur beim Verwenden")
        case .denied, .restricted:
            return lt("Nicht erlaubt")
        default:
            return lt("Unbekannt")
        }
    }

    private var accuracyLabel: String {
        switch location.accuracyAuthorization {
        case .fullAccuracy:
            return lt("Voll")
        case .reducedAccuracy:
            return lt("Reduziert")
        @unknown default:
            return lt("Unbekannt")
        }
    }

    private var backgroundRefreshLabel: String {
        switch UIApplication.shared.backgroundRefreshStatus {
        case .available:
            return lt("Aktiv")
        case .denied, .restricted:
            return lt("Nicht aktiv")
        @unknown default:
            return lt("Unbekannt")
        }
    }

    private func guideCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon)
                .font(.headline)
            content()
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func guideList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func statusRow(title: String, value: String, isGood: Bool) -> some View {
        HStack {
            Label(title, systemImage: isGood ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(isGood ? .green : .orange)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }
}
