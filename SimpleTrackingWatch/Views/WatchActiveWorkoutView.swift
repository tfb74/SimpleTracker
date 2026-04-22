import SwiftUI

struct WatchActiveWorkoutView: View {
    @Environment(WatchWorkoutService.self) private var workoutService
    @Environment(UserSettings.self)        private var settings

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1.0)) { _ in
            VStack(spacing: 6) {
                // Type + elapsed
                HStack {
                    Image(systemName: workoutService.currentWorkoutType.systemImage)
                        .font(.caption2)
                    Text(workoutService.elapsedSeconds.watchFormatted)
                        .font(.title3.monospacedDigit().bold())
                }
                .foregroundStyle(.secondary)

                Divider()

                // Distance
                HStack {
                    Image(systemName: "map").font(.caption2).foregroundStyle(.blue)
                    Text(settings.unitPreference.formatted(meters: workoutService.currentMetrics.distanceMeters))
                        .font(.headline.monospacedDigit())
                }

                // Metrics row
                HStack(spacing: 12) {
                    VStack(spacing: 0) {
                        Text(String(format: "%.0f", workoutService.currentMetrics.activeCalories))
                            .font(.subheadline.monospacedDigit().bold())
                        Text("kcal").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(spacing: 0) {
                        Text(workoutService.currentMetrics.heartRate > 0
                             ? String(format: "%.0f", workoutService.currentMetrics.heartRate)
                             : "--")
                            .font(.subheadline.monospacedDigit().bold())
                        Text("bpm").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(spacing: 0) {
                        Text(paceLabel)
                            .font(.caption.monospacedDigit().bold())
                        Text(settings.unitPreference == .metric ? "/km" : "/mi")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }

                // Controls
                HStack(spacing: 16) {
                    Button {
                        workoutService.isPaused ? workoutService.resumeWorkout() : workoutService.pauseWorkout()
                    } label: {
                        Image(systemName: workoutService.isPaused ? "play.fill" : "pause.fill")
                    }
                    .tint(.yellow)
                    .buttonStyle(.borderedProminent)

                    Button {
                        Task { try? await workoutService.stopWorkout() }
                    } label: {
                        Image(systemName: "stop.fill")
                    }
                    .tint(.red)
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var paceLabel: String {
        let speed = workoutService.currentMetrics.currentSpeedMPS
        guard speed > 0 else { return "--:--" }
        let intervalMeters: Double = settings.unitPreference == .metric ? 1_000 : 1_609.344
        let sec = intervalMeters / speed
        return String(format: "%d:%02d", Int(sec) / 60, Int(sec) % 60)
    }
}

extension TimeInterval {
    var watchFormatted: String {
        let h = Int(self) / 3_600
        let m = (Int(self) % 3_600) / 60
        let s = Int(self) % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }
}
