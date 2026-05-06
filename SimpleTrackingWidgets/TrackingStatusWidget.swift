import SwiftUI
import WidgetKit

struct TrackingTimelineEntry: TimelineEntry {
    let date: Date
    let snapshot: TrackingSnapshot
    let statistics: TrackingStatisticsSnapshot
    let scene: TrackingWidgetScene
}

struct TrackingTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TrackingTimelineEntry {
        TrackingTimelineEntry(
            date: Date(),
            snapshot: .previewActive,
            statistics: .preview,
            scene: .automatic
        )
    }

    func snapshot(for configuration: TrackingWidgetIntent, in context: Context) async -> TrackingTimelineEntry {
        TrackingTimelineEntry(
            date: Date(),
            snapshot: context.isPreview ? .previewActive : TrackingWidgetStore.loadSnapshot(),
            statistics: context.isPreview ? .preview : TrackingWidgetStore.loadStatisticsSnapshot(),
            scene: configuration.scene
        )
    }

    func timeline(for configuration: TrackingWidgetIntent, in context: Context) async -> Timeline<TrackingTimelineEntry> {
        let snapshot = TrackingWidgetStore.loadSnapshot()
        let entry = TrackingTimelineEntry(
            date: Date(),
            snapshot: snapshot,
            statistics: TrackingWidgetStore.loadStatisticsSnapshot(),
            scene: configuration.scene
        )
        let nextRefresh = Calendar.current.date(
            byAdding: .minute,
            value: snapshot.isActive ? 15 : 45,
            to: Date()
        ) ?? Date().addingTimeInterval(snapshot.isActive ? 15 * 60 : 45 * 60)

        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }
}

struct TrackingStatusWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: TrackingWidgetConstants.widgetKind,
            intent: TrackingWidgetIntent.self,
            provider: TrackingTimelineProvider()
        ) { entry in
            TrackingStatusWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetBackground(snapshot: entry.snapshot)
                }
                .widgetURL(entry.snapshot.isActive ? TrackingWidgetConstants.workoutURL : TrackingWidgetConstants.todayURL)
        }
        .configurationDisplayName("SimpleTracking")
        .description("Live-Workout oder wählbare Statistik für Home- und Sperrbildschirm.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

private struct TrackingStatusWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: TrackingTimelineEntry

    var body: some View {
        switch family {
        case .systemMedium:
            mediumWidget
        case .systemLarge:
            largeWidget
        case .accessoryInline:
            accessoryInline
        case .accessoryCircular:
            accessoryCircular
        case .accessoryRectangular:
            accessoryRectangular
        default:
            smallWidget
        }
    }

    private var snapshot: TrackingSnapshot {
        entry.snapshot
    }

    private var statistics: TrackingStatisticsSnapshot {
        entry.statistics
    }

    private var scene: TrackingWidgetScene {
        entry.scene == .automatic ? .overview : entry.scene
    }

    private var smallWidget: some View {
        Group {
            if snapshot.isActive {
                activeSmallWidget
            } else {
                statSmallWidget
            }
        }
        .padding(16)
    }

    private var mediumWidget: some View {
        Group {
            if snapshot.isActive {
                activeMediumWidget
            } else {
                statMediumWidget
            }
        }
        .padding(16)
    }

    private var largeWidget: some View {
        Group {
            if snapshot.isActive {
                activeLargeWidget
            } else {
                statLargeWidget
            }
        }
        .padding(18)
    }

    private var activeSmallWidget: some View {
        VStack(alignment: .leading, spacing: 8) {
            widgetHeader(title: "Live", icon: snapshot.systemImageName, color: .green)

            Spacer(minLength: 0)

            if let startDate = snapshot.startDate {
                Text(startDate, style: .timer)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .contentTransition(.numericText())
                    .minimumScaleFactor(0.72)
            }
            Text(snapshot.formattedDistance)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var activeMediumWidget: some View {
        HStack(spacing: 16) {
            activeIcon(size: 64, imageSize: 30)

            VStack(alignment: .leading, spacing: 8) {
                Text("Tracking läuft")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                Text(snapshot.workoutName)
                    .font(.headline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                HStack(spacing: 12) {
                    metric("timer", activeDurationValue)
                    metric("map", snapshot.compactDistance)
                    metric("speedometer", snapshot.formattedPace)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var activeLargeWidget: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                activeIcon(size: 58, imageSize: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Tracking läuft")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                    Text(snapshot.workoutName)
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                liveTile("Zeit", activeDurationValue, "timer", .primary)
                liveTile("Distanz", snapshot.formattedDistance, "map", .green)
                liveTile("Tempo", snapshot.formattedPace, "speedometer", .purple)
                liveTile("Heute", statistics.compactDistance, "figure.walk", .blue)
            }
        }
    }

    private var statSmallWidget: some View {
        let item = primaryStat
        return VStack(alignment: .leading, spacing: 8) {
            widgetHeader(title: item.title, icon: item.icon, color: item.color)

            Spacer(minLength: 0)

            Text(item.value)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.58)
            Text(item.subtitle)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private var statMediumWidget: some View {
        VStack(alignment: .leading, spacing: 12) {
            widgetHeader(title: sceneTitle, icon: primaryStat.icon, color: primaryStat.color)

            HStack(spacing: 10) {
                ForEach(statItems.prefix(3)) { item in
                    statTile(item)
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var statLargeWidget: some View {
        VStack(alignment: .leading, spacing: 16) {
            widgetHeader(title: sceneTitle, icon: primaryStat.icon, color: primaryStat.color)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(statItems.prefix(4)) { item in
                    statTile(item)
                }
            }

            Spacer(minLength: 0)

            Text("Aktualisiert \(statistics.lastUpdated, style: .time)")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var accessoryInline: some View {
        if snapshot.isActive {
            Text("\(snapshot.workoutName) \(snapshot.compactDistance)")
        } else {
            Text("\(primaryStat.title) \(primaryStat.value)")
        }
    }

    private var accessoryCircular: some View {
        Gauge(value: circularProgress) {
            Image(systemName: snapshot.isActive ? snapshot.systemImageName : primaryStat.icon)
        } currentValueLabel: {
            Text(snapshot.isActive ? snapshot.compactDistance : primaryStat.compactValue)
                .minimumScaleFactor(0.55)
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }

    private var accessoryRectangular: some View {
        HStack(spacing: 8) {
            Image(systemName: snapshot.isActive ? snapshot.systemImageName : primaryStat.icon)
                .font(.headline.weight(.semibold))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.isActive ? "Live" : primaryStat.title)
                    .font(.caption2.weight(.semibold))
                if snapshot.isActive, let startDate = snapshot.startDate {
                    (Text(startDate, style: .timer) + Text(" · \(snapshot.compactDistance)"))
                        .font(.headline.weight(.bold))
                        .minimumScaleFactor(0.68)
                } else {
                    Text("\(primaryStat.value) · \(primaryStat.subtitle)")
                        .font(.headline.weight(.bold))
                        .minimumScaleFactor(0.68)
                        .lineLimit(1)
                }
            }
        }
    }

    private var activeDurationValue: String {
        guard snapshot.startDate != nil else { return "0:00" }
        return snapshot.formattedDuration(at: entry.date)
    }

    private var sceneTitle: String {
        switch scene {
        case .automatic, .overview:
            return "Heute Überblick"
        case .activity:
            return "Aktivität"
        case .energy:
            return "Energie-Bilanz"
        case .nutrition:
            return "Ernährung"
        case .workouts:
            return "Workouts"
        case .distance:
            return "Distanz"
        }
    }

    private var primaryStat: WidgetStatItem {
        switch scene {
        case .automatic, .overview:
            return WidgetStatItem(
                title: "Schritte",
                value: statistics.steps.formatted(),
                compactValue: compactCount(statistics.steps),
                subtitle: "heute",
                icon: "figure.walk",
                color: .blue
            )
        case .activity:
            return WidgetStatItem(
                title: "Bewegung",
                value: "\(Int(statistics.activeCalories.rounded())) kcal",
                compactValue: "\(Int(statistics.activeCalories.rounded()))",
                subtitle: "\(statistics.steps.formatted()) Schritte",
                icon: "flame.fill",
                color: .orange
            )
        case .energy:
            return WidgetStatItem(
                title: "Bilanz",
                value: signedKcal(statistics.energyBalance),
                compactValue: signedCompact(statistics.energyBalance),
                subtitle: "Aufnahme minus Aktivität",
                icon: "arrow.left.arrow.right.circle.fill",
                color: statistics.energyBalance > 0 ? .red : .green
            )
        case .nutrition:
            return WidgetStatItem(
                title: "Aufgenommen",
                value: "\(Int(statistics.consumedCalories.rounded())) kcal",
                compactValue: "\(Int(statistics.consumedCalories.rounded()))",
                subtitle: "\(String(format: "%.1f", statistics.breadUnits)) BE",
                icon: "fork.knife",
                color: .red
            )
        case .workouts:
            return WidgetStatItem(
                title: "Workouts",
                value: "\(statistics.workoutCountToday)",
                compactValue: "\(statistics.workoutCountToday)",
                subtitle: statistics.bestScore.map { "Bestscore \($0)" } ?? "heute",
                icon: "figure.run",
                color: .purple
            )
        case .distance:
            return WidgetStatItem(
                title: "Distanz",
                value: statistics.formattedDistance,
                compactValue: statistics.compactDistance,
                subtitle: "heute",
                icon: "map.fill",
                color: .green
            )
        }
    }

    private var statItems: [WidgetStatItem] {
        switch scene {
        case .automatic, .overview:
            return [
                primaryStat,
                WidgetStatItem(title: "Bewegung", value: "\(Int(statistics.activeCalories.rounded()))", compactValue: "\(Int(statistics.activeCalories.rounded()))", subtitle: "kcal", icon: "flame.fill", color: .orange),
                WidgetStatItem(title: "Distanz", value: statistics.compactDistance, compactValue: statistics.compactDistance, subtitle: statistics.unit.distanceLabel, icon: "map.fill", color: .green),
                WidgetStatItem(title: "Aufnahme", value: "\(Int(statistics.consumedCalories.rounded()))", compactValue: "\(Int(statistics.consumedCalories.rounded()))", subtitle: "kcal", icon: "fork.knife", color: .red)
            ]
        case .activity:
            return [
                primaryStat,
                WidgetStatItem(title: "Schritte", value: statistics.steps.formatted(), compactValue: compactCount(statistics.steps), subtitle: "heute", icon: "figure.walk", color: .blue),
                WidgetStatItem(title: "Distanz", value: statistics.compactDistance, compactValue: statistics.compactDistance, subtitle: statistics.unit.distanceLabel, icon: "location.fill", color: .green),
                WidgetStatItem(title: "Workouts", value: "\(statistics.workoutCountToday)", compactValue: "\(statistics.workoutCountToday)", subtitle: "heute", icon: "figure.run", color: .purple)
            ]
        case .energy:
            return [
                primaryStat,
                WidgetStatItem(title: "Aufgenommen", value: "\(Int(statistics.consumedCalories.rounded()))", compactValue: "\(Int(statistics.consumedCalories.rounded()))", subtitle: "kcal", icon: "fork.knife", color: .red),
                WidgetStatItem(title: "Bewegung", value: "\(Int(statistics.activeCalories.rounded()))", compactValue: "\(Int(statistics.activeCalories.rounded()))", subtitle: "kcal", icon: "flame.fill", color: .orange),
                WidgetStatItem(title: "BE", value: String(format: "%.1f", statistics.breadUnits), compactValue: String(format: "%.0f", statistics.breadUnits), subtitle: "heute", icon: "square.grid.2x2.fill", color: .purple)
            ]
        case .nutrition:
            return [
                primaryStat,
                WidgetStatItem(title: "Carbs", value: "\(Int(statistics.carbsGrams.rounded())) g", compactValue: "\(Int(statistics.carbsGrams.rounded()))", subtitle: "Kohlenhydrate", icon: "leaf.fill", color: .green),
                WidgetStatItem(title: "BE", value: String(format: "%.1f", statistics.breadUnits), compactValue: String(format: "%.0f", statistics.breadUnits), subtitle: "heute", icon: "square.grid.2x2.fill", color: .purple),
                WidgetStatItem(title: "Einträge", value: "\(statistics.foodEntryCount)", compactValue: "\(statistics.foodEntryCount)", subtitle: "heute", icon: "list.bullet", color: .blue)
            ]
        case .workouts:
            return [
                primaryStat,
                WidgetStatItem(title: "Workout-km", value: statistics.formattedWorkoutDistance, compactValue: statistics.formattedWorkoutDistance, subtitle: "heute", icon: "map", color: .green),
                WidgetStatItem(title: "Bestscore", value: statistics.bestScore.map(String.init) ?? "--", compactValue: statistics.bestScore.map(String.init) ?? "--", subtitle: "gesamt", icon: "star.fill", color: .yellow),
                WidgetStatItem(title: "Bewegung", value: "\(Int(statistics.activeCalories.rounded()))", compactValue: "\(Int(statistics.activeCalories.rounded()))", subtitle: "kcal", icon: "flame.fill", color: .orange)
            ]
        case .distance:
            return [
                primaryStat,
                WidgetStatItem(title: "Workout", value: statistics.formattedWorkoutDistance, compactValue: statistics.formattedWorkoutDistance, subtitle: "heute", icon: "figure.run", color: .purple),
                WidgetStatItem(title: "Schritte", value: statistics.steps.formatted(), compactValue: compactCount(statistics.steps), subtitle: "heute", icon: "figure.walk", color: .blue),
                WidgetStatItem(title: "Bewegung", value: "\(Int(statistics.activeCalories.rounded()))", compactValue: "\(Int(statistics.activeCalories.rounded()))", subtitle: "kcal", icon: "flame.fill", color: .orange)
            ]
        }
    }

    private var circularProgress: Double {
        if snapshot.isActive {
            return snapshot.distanceProgressToNextUnit
        }

        switch scene {
        case .automatic, .overview, .activity:
            return min(Double(statistics.steps) / 10_000, 1)
        case .energy:
            let total = max(statistics.activeCalories, statistics.consumedCalories, 1)
            return min(statistics.consumedCalories / total, 1)
        case .nutrition:
            return min(statistics.carbsGrams / 250, 1)
        case .workouts:
            return min(Double(statistics.workoutCountToday) / 1, 1)
        case .distance:
            return min(statistics.distanceMeters / statistics.unit.unitMeters, 1)
        }
    }

    private func widgetHeader(title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.headline.weight(.semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    private func activeIcon(size: CGFloat, imageSize: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(.green.opacity(0.18))
            Image(systemName: snapshot.systemImageName)
                .font(.system(size: imageSize, weight: .semibold))
                .foregroundStyle(.green)
        }
        .frame(width: size, height: size)
    }

    private func liveTile(_ title: String, _ value: String, _ icon: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
    }

    private func statTile(_ item: WidgetStatItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(item.title, systemImage: item.icon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(item.color)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
            Text(item.value)
                .font(.headline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.58)
            Text(item.subtitle)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.secondary.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
    }

    private func metric(_ image: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: image)
                .font(.caption2.weight(.semibold))
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(.secondary)
    }

    private func compactCount(_ value: Int) -> String {
        if value >= 10_000 {
            return String(format: "%.0fk", Double(value) / 1_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fk", Double(value) / 1_000)
        }
        return "\(value)"
    }

    private func signedKcal(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        return rounded > 0 ? "+\(rounded) kcal" : "\(rounded) kcal"
    }

    private func signedCompact(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        return rounded > 0 ? "+\(rounded)" : "\(rounded)"
    }
}

private struct WidgetStatItem: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let compactValue: String
    let subtitle: String
    let icon: String
    let color: Color
}

private struct WidgetBackground: View {
    let snapshot: TrackingSnapshot

    var body: some View {
        ZStack {
            Color(.systemBackground)
            if snapshot.isActive {
                LinearGradient(
                    colors: [.green.opacity(0.26), .blue.opacity(0.14), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }
}

#Preview(as: .accessoryRectangular) {
    TrackingStatusWidget()
} timeline: {
    TrackingTimelineEntry(date: Date(), snapshot: .previewActive, statistics: .preview, scene: .automatic)
    TrackingTimelineEntry(date: Date(), snapshot: .idle, statistics: .preview, scene: .energy)
    TrackingTimelineEntry(date: Date(), snapshot: .idle, statistics: .preview, scene: .nutrition)
}
