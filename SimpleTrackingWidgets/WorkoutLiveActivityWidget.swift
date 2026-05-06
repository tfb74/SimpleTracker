import ActivityKit
import SwiftUI
import WidgetKit

struct WorkoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            WorkoutLiveActivityLockScreenView(context: context)
                .activityBackgroundTint(Color(.systemBackground))
                .activitySystemActionForegroundColor(.green)
                .widgetURL(TrackingWidgetConstants.workoutURL)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LiveActivityMetric(
                        title: "Zeit",
                        systemImage: "timer",
                        content: Text(context.attributes.startDate, style: .timer)
                    )
                }
                DynamicIslandExpandedRegion(.trailing) {
                    LiveActivityMetric(
                        title: "Distanz",
                        systemImage: "map",
                        content: Text(context.state.compactDistance)
                    )
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        Image(systemName: context.attributes.systemImageName)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.green)
                        Text(context.attributes.workoutName)
                            .font(.headline.weight(.bold))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Label(context.state.formattedPace, systemImage: "speedometer")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: context.attributes.systemImageName)
                    .foregroundStyle(.green)
            } compactTrailing: {
                Text(context.state.compactDistance)
                    .font(.caption2.weight(.semibold))
                    .minimumScaleFactor(0.72)
            } minimal: {
                Image(systemName: context.attributes.systemImageName)
                    .foregroundStyle(.green)
            }
            .widgetURL(TrackingWidgetConstants.workoutURL)
        }
    }
}

private struct WorkoutLiveActivityLockScreenView: View {
    let context: ActivityViewContext<WorkoutActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: context.attributes.systemImageName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.green)
                    .frame(width: 30, height: 30)
                    .background(.green.opacity(0.16), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.workoutName)
                        .font(.headline.weight(.bold))
                        .lineLimit(1)
                    Text("Tracking läuft")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Text(context.attributes.startDate, style: .timer)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.72)
            }

            HStack(spacing: 10) {
                LiveActivityMetric(
                    title: "Distanz",
                    systemImage: "map",
                    content: Text(context.state.formattedDistance)
                )

                LiveActivityMetric(
                    title: "Tempo",
                    systemImage: "speedometer",
                    content: Text(context.state.formattedPace)
                )
            }
        }
        .padding(16)
    }
}

private struct LiveActivityMetric: View {
    let title: String
    let systemImage: String
    let content: Text

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            content
                .font(.headline.weight(.bold))
                .minimumScaleFactor(0.72)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Live Activity", as: .content, using: WorkoutActivityAttributes(
    workoutName: "Laufen",
    systemImageName: "figure.run",
    startDate: Date().addingTimeInterval(-1_842)
)) {
    WorkoutLiveActivityWidget()
} contentStates: {
    WorkoutActivityAttributes.ContentState(
        distanceMeters: 4_280,
        speedMetersPerSecond: 3.05,
        lastUpdated: Date(),
        unit: .metric
    )
}
