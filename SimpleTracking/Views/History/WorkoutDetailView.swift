import SwiftUI

struct WorkoutDetailView: View {
    let workout: WorkoutRecord
    @Environment(UserSettings.self) private var settings
    @Environment(HealthKitService.self) private var healthKit
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var deleteStatus: String?

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                if geo.size.width > geo.size.height {
                    HStack(alignment: .top, spacing: 16) {
                        mapSection.frame(width: geo.size.width * 0.48, height: geo.size.height - 32)
                        metricsSection
                    }
                    .padding()
                } else {
                    VStack(spacing: 16) {
                        mapSection.frame(height: 300)
                        metricsSection.padding(.horizontal)
                    }
                    .padding(.vertical)
                }
            }
        }
        .navigationTitle(workout.workoutType.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(isDeleting)
            }
        }
        .confirmationDialog(
            "Workout löschen?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Löschen", role: .destructive) {
                Task { await performDelete() }
            }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("Das Workout wird endgültig entfernt. Falls es von SimpleTracking in Apple Health geschrieben wurde, wird es auch dort gelöscht.")
        }
        .overlay {
            if isDeleting {
                ProgressView("Lösche…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private func performDelete() async {
        isDeleting = true
        _ = await healthKit.deleteWorkout(workout)
        isDeleting = false
        dismiss()
    }

    private var mapSection: some View {
        Group {
            if workout.route.count >= 2 {
                StaticRouteMapView(routePoints: workout.route)
            } else {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.secondary.opacity(0.15))
                    .overlay { Label("Keine Route", systemImage: "map").foregroundStyle(.secondary) }
            }
        }
    }

    private var metricsSection: some View {
        VStack(spacing: 14) {
            // Score
            ScoreBreakdownView(score: workout.score(settings: settings))

            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text(workout.startDate.formatted(date: .complete, time: .shortened))
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(workout.duration.formatted).font(.title.bold())
                }
                Spacer()
                Image(systemName: workout.workoutType.systemImage)
                    .font(.system(size: 40)).foregroundStyle(Color.accentColor)
            }
            Divider()

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                DetailMetric(label: "Distanz",
                             value: workout.formattedDistance(unit: settings.unitPreference),
                             icon: "map", color: .blue)
                DetailMetric(label: "Kalorien",
                             value: String(format: "%.0f kcal", workout.activeCalories),
                             icon: "flame", color: .orange)
                DetailMetric(label: "Schritte",
                             value: workout.steps > 0 ? workout.steps.formatted() : "--",
                             icon: "figure.walk", color: .green)
                DetailMetric(label: settings.unitPreference == .metric ? "Ø Tempo" : "Ø Pace",
                             value: settings.unitPreference == .metric ? workout.pacePerKm : workout.pacePerMile,
                             icon: "speedometer", color: .purple)
                DetailMetric(label: "Max. Tempo",
                             value: settings.unitPreference == .metric
                                 ? String(format: "%.1f km/h", workout.maxSpeedKmh)
                                 : String(format: "%.1f mph", workout.maxSpeedMPS * 2.23694),
                             icon: "gauge.open.with.lines.needle.67percent", color: .red)
                if workout.heartRateAvg > 0 {
                    DetailMetric(label: "Ø Herzrate",
                                 value: String(format: "%.0f bpm", workout.heartRateAvg),
                                 icon: "heart.fill", color: .pink)
                }
            }
        }
    }
}

struct DetailMetric: View {
    let label: String
    let value: String
    let icon:  String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: icon).font(.caption).foregroundStyle(color)
            Text(value).font(.title3.bold()).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
