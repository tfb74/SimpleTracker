import SwiftUI
import Charts

// MARK: - Period

enum StatsPeriod: String, CaseIterable, Identifiable {
    case today    = "Heute"
    case week     = "Woche"
    case month    = "Monat"
    case quarter  = "3 Mon."
    case year     = "Jahr"

    var id: String { rawValue }

    /// Anzahl Tage, die wir für Diagramme/Aggregate anschauen.
    var days: Int {
        switch self {
        case .today:   return 1
        case .week:    return 7
        case .month:   return 30
        case .quarter: return 90
        case .year:    return 365
        }
    }

    /// Schrittweite der X-Achse im Chart.
    var axisStride: Calendar.Component {
        switch self {
        case .today:             return .hour
        case .week:              return .day
        case .month:             return .weekOfYear
        case .quarter, .year:    return .month
        }
    }
}

// MARK: - Per-Day Aggregat

struct DayStat: Identifiable, Hashable {
    let id = UUID()
    let date:          Date
    let steps:         Int
    let caloriesHK:    Double   // Active Energy aus HealthKit (Tagessumme)
    let distanceKmHK:  Double   // Walking/Running + Cycling aus HealthKit
    let kcalIn:        Double   // aus FoodLog
    let carbsIn:       Double   // g
    let workoutCount:  Int      // Workouts aus healthKit.workouts an diesem Tag
    let workoutKcal:   Double   // Summe activeCalories der Workouts
    let workoutKm:     Double   // Summe distanceKm der Workouts
    let restingKcal:   Double   // Geschätzter Ruheumsatz für diesen Tag
    let carbTargetLow: Double   // g
    let carbTargetHigh: Double  // g

    var beIn: Double { carbsIn / 12.0 }

    /// „Tatsächlich verbrauchte" Kalorien — max aus HK-Tagessumme und
    /// aufsummierten Workouts. Das ist robust gegen den Fall, dass HealthKit
    /// ein frisch gespeichertes Workout noch nicht in die aggregierten
    /// Quantity-Samples übernommen hat.
    var caloriesOut: Double { max(caloriesHK, workoutKcal) }
    var totalCaloriesOut: Double { restingKcal + caloriesOut }
    var distanceKm:  Double { max(distanceKmHK, workoutKm) }

    var restingBalance: Double { kcalIn - restingKcal }
    var totalBalance: Double { kcalIn - totalCaloriesOut }
}

// MARK: - View

struct StatisticsView: View {
    @Environment(HealthKitService.self) private var healthKit
    @Environment(UserSettings.self)     private var settings
    @Environment(FoodLogStore.self)     private var foodLog

    @State private var period:   StatsPeriod = .week
    @State private var stats:    [DayStat]   = []
    @State private var isLoading             = false
    @State private var lastLoadedAt: Date?   = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 24) {
                    periodPicker

                    if isLoading && stats.isEmpty {
                        ProgressView().frame(height: 200)
                    } else {
                        todaySection
                        if period != .today {
                            activitySection
                            workoutTypeSection
                            energyBalanceSection
                            NativeAdTile()
                            nutritionSection
                            personalRecordsSection
                        }
                        consistencyHeatmap
                    }
                }
                .padding(.vertical)
            }
            .refreshable { await load(force: true) }
            .appChrome(title: lt("Statistiken"), accent: .teal, metrics: headerMetrics)
            .task { await loadIfNeeded() }
            .onAppear { Task { await loadIfNeeded() } }
            .onChange(of: period)                      { _, _ in Task { await load(force: true) } }
            .onChange(of: foodLog.entries.count)       { _, _ in Task { await load(force: true) } }
            .onChange(of: healthKit.workouts.count)    { _, _ in Task { await load(force: true) } }
            .onChange(of: settings.ageYears)           { _, _ in Task { await load(force: true) } }
            .onChange(of: settings.weightKg)           { _, _ in Task { await load(force: true) } }
            .onChange(of: settings.heightCm)           { _, _ in Task { await load(force: true) } }
        }
    }

    private var headerMetrics: [AppHeaderMetric] {
        let workoutCount = workoutsInPeriod.count
        let totalDistance = stats.reduce(0.0) { $0 + $1.distanceKm }

        return [
            AppHeaderMetric(
                title: lt("Workout"),
                value: "\(workoutCount)",
                systemImage: "figure.run",
                tint: .purple
            ),
            AppHeaderMetric(
                title: lt("Distanz"),
                value: formattedDistance(totalDistance),
                systemImage: "map.fill",
                tint: .green
            )
        ]
    }

    // MARK: Period Picker

    private var periodPicker: some View {
        Picker("Zeitraum", selection: $period) {
            ForEach(StatsPeriod.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }

    // MARK: - Heute

    private var todayWorkouts: [WorkoutRecord] {
        let cal = Calendar.current
        return healthKit.workouts
            .filter { cal.isDateInToday($0.startDate) }
            .sorted { $0.startDate > $1.startDate }
    }

    @ViewBuilder
    private var todaySection: some View {
        let today = stats.last   // letzter Tag im Array = heute

        StatsSection(title: "Heute", systemImage: "sun.max.fill") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                MetricTile(
                    title: "Schritte",
                    value: (today?.steps ?? healthKit.todaySteps).formatted(),
                    icon: "figure.walk", color: .blue
                )
                MetricTile(
                    title: lt("Bewegung"),
                    value: String(format: "%.0f kcal", today?.caloriesOut ?? healthKit.todayCalories),
                    icon: "flame.fill", color: .orange
                )
                MetricTile(
                    title: settings.unitPreference.distanceLabel.capitalized,
                    value: formattedDistance(today?.distanceKm ?? healthKit.todayDistanceKm),
                    icon: "location.fill", color: .green
                )
                MetricTile(
                    title: "Aufgenommen",
                    value: String(format: "%.0f kcal", foodLog.totals(on: Date()).kcal),
                    icon: "fork.knife", color: .red
                )
            }

            if let today {
                EnergySnapshotCard(
                    title: lt("Energie heute"),
                    intakeTitle: lt("Aufgenommen"),
                    baselineTitle: lt("Grundbedarf bis jetzt"),
                    movementTitle: lt("Bewegung"),
                    totalTitle: lt("Gesamtverbrauch bis jetzt"),
                    baselineBalanceTitle: lt("Bilanz vs Grundbedarf"),
                    totalBalanceTitle: lt("Bilanz inkl. Bewegung"),
                    baselineCompareTitle: lt("gegen Grundbedarf"),
                    totalCompareTitle: lt("inkl. Bewegung"),
                    hint: lt("Bewegung = Apple-Health-Aktivkalorien aus Gehen, Schritten, Alltagsaktivität und Workouts - nicht aus Nahrung."),
                    intakeKcal: today.kcalIn,
                    restingKcal: today.restingKcal,
                    activeKcal: today.caloriesOut,
                    totalKcal: today.totalCaloriesOut,
                    baselineBalance: today.restingBalance,
                    totalBalance: today.totalBalance
                )
            }

            if !todayWorkouts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(todayWorkouts.count) \(todayWorkouts.count == 1 ? "Workout" : "Workouts") heute")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(todayWorkouts) { w in
                        TodayWorkoutRow(workout: w, settings: settings)
                    }
                }
                .padding(.top, 4)
            } else {
                Label("Noch kein Workout heute", systemImage: "figure.run.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - Aktivität (Workouts pro Tag)

    private var activitySection: some View {
        let total       = stats.reduce(0) { $0 + $1.workoutCount }
        let totalKm     = stats.reduce(0.0) { $0 + $1.workoutKm }
        let totalKcal   = stats.reduce(0.0) { $0 + $1.caloriesOut }
        let totalSteps  = stats.reduce(0)   { $0 + $1.steps }
        let activeDays  = stats.filter { $0.workoutCount > 0 }.count

        return StatsSection(title: "Aktivität", systemImage: "chart.bar.fill") {
            Chart(stats) { s in
                BarMark(
                    x: .value("Tag", s.date, unit: .day),
                    y: .value("kcal", s.caloriesOut)
                )
                .foregroundStyle(Color.orange.gradient)
                .cornerRadius(3)
            }
            .chartXAxis { periodAxis }
            .chartYAxis { countAxis }
            .frame(height: 180)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                MetricTile(title: "Workouts",     value: "\(total)",                           icon: "figure.run",      color: .purple)
                MetricTile(title: "Aktive Tage",  value: "\(activeDays) / \(stats.count)",     icon: "calendar",        color: .teal)
                MetricTile(title: "Distanz",      value: formattedDistance(totalKm),           icon: "map.fill",        color: .green)
                MetricTile(title: "Ø Schritte",   value: "\(totalSteps / max(1, stats.count))", icon: "figure.walk",    color: .blue)
                MetricTile(title: "Verbraucht",   value: String(format: "%.0f kcal", totalKcal), icon: "flame.fill",    color: .orange)
                MetricTile(title: "Ø Tag",        value: String(format: "%.0f kcal", totalKcal / Double(max(1, stats.count))), icon: "chart.line.uptrend.xyaxis", color: .pink)
            }
        }
    }

    // MARK: - Workout-Typen Breakdown

    private var workoutsInPeriod: [WorkoutRecord] {
        guard let first = stats.first?.date else { return [] }
        return healthKit.workouts.filter { $0.startDate >= Calendar.current.startOfDay(for: first) }
    }

    private var workoutTypeBreakdown: [(type: WorkoutType, count: Int, km: Double, kcal: Double)] {
        let grouped = Dictionary(grouping: workoutsInPeriod, by: { $0.workoutType })
        return grouped.map { (type, list) in
            (type: type,
             count: list.count,
             km: list.reduce(0.0) { $0 + $1.distanceKm },
             kcal: list.reduce(0.0) { $0 + $1.activeCalories })
        }
        .sorted { $0.count > $1.count }
    }

    @ViewBuilder
    private var workoutTypeSection: some View {
        let breakdown = workoutTypeBreakdown
        if !breakdown.isEmpty {
            let maxCount = breakdown.first?.count ?? 1
            StatsSection(title: "Nach Sportart", systemImage: "figure.mixed.cardio") {
                VStack(spacing: 8) {
                    ForEach(breakdown, id: \.type) { row in
                        WorkoutTypeBar(
                            type: row.type,
                            count: row.count,
                            km: row.km,
                            kcal: row.kcal,
                            fraction: Double(row.count) / Double(max(1, maxCount)),
                            distanceLabel: settings.unitPreference.distanceLabel,
                            formattedDistance: formattedDistance(row.km)
                        )
                    }
                }
            }
        }
    }

    // MARK: - Energiebilanz

    private var energyBalanceSection: some View {
        let resting  = stats.reduce(0.0) { $0 + $1.restingKcal }
        let active   = stats.reduce(0.0) { $0 + $1.caloriesOut }
        let burned   = stats.reduce(0.0) { $0 + $1.totalCaloriesOut }
        let consumed = stats.reduce(0.0) { $0 + $1.kcalIn }
        let restingBalance = consumed - resting
        let totalBalance   = consumed - burned
        let restingBalanceColor: Color = restingBalance > 0 ? .red : .green
        let totalBalanceColor: Color = totalBalance > 0 ? .red : .green
        let count = max(1, stats.count)

        return StatsSection(title: "Energiebilanz", systemImage: "flame.circle.fill") {
            Chart {
                ForEach(stats) { s in
                    LineMark(x: .value("Tag", s.date), y: .value("kcal", s.totalCaloriesOut), series: .value("Serie", "Gesamtverbrauch"))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color.orange.gradient)
                    LineMark(x: .value("Tag", s.date), y: .value("kcal", s.kcalIn), series: .value("Serie", "Aufgenommen"))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Color.red.gradient)
                }
            }
            .chartForegroundStyleScale(["Gesamtverbrauch": .orange, "Aufgenommen": .red])
            .chartLegend(position: .bottom, spacing: 8)
            .chartXAxis { periodAxis }
            .chartYAxis { countAxis }
            .frame(height: 200)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                MetricTile(title: lt("Grundbedarf"),   value: String(format: "%.0f kcal", resting),                 icon: "bed.double.fill", color: .indigo)
                MetricTile(title: lt("Aktivität"),     value: String(format: "%.0f kcal", active),                  icon: "figure.run", color: .orange)
                MetricTile(title: lt("Gesamtverbrauch"), value: String(format: "%.0f kcal", burned),                icon: "flame.fill", color: .orange)
                MetricTile(title: "Aufgenommen",   value: String(format: "%.0f kcal", consumed),                icon: "fork.knife", color: .red)
                MetricTile(title: lt("Ø Gesamt/Tag"),  value: String(format: "%.0f kcal", burned / Double(count)),  icon: "minus.circle", color: .orange)
                MetricTile(title: lt("Ø aufgenommen"), value: String(format: "%.0f kcal", consumed / Double(count)), icon: "plus.circle",  color: .red)
                MetricTile(
                    title: lt("Bilanz vs Grundbedarf"),
                    value: signedKcal(restingBalance),
                    icon: restingBalance > 0 ? "arrow.up.forward" : "arrow.down.forward",
                    color: restingBalanceColor
                )
                MetricTile(
                    title: lt("Bilanz inkl. Bewegung"),
                    value: signedKcal(totalBalance),
                    icon: totalBalance > 0 ? "arrow.up.forward" : "arrow.down.forward",
                    color: totalBalanceColor
                )
                MetricTile(
                    title: lt("Ø vs Grundbedarf"),
                    value: signedKcal(restingBalance / Double(count)),
                    icon: "scalemass",
                    color: restingBalanceColor
                )
                MetricTile(
                    title: lt("Ø inkl. Bewegung"),
                    value: signedKcal(totalBalance / Double(count)),
                    icon: "scalemass",
                    color: totalBalanceColor
                )
            }
        }
    }

    // MARK: - Ernährung

    private var nutritionSection: some View {
        let totalCarbs = stats.reduce(0.0) { $0 + $1.carbsIn }
        let totalBE    = stats.reduce(0.0) { $0 + $1.beIn }
        let count = max(1, stats.count)
        let avgCarbLow  = stats.reduce(0.0) { $0 + $1.carbTargetLow } / Double(count)
        let avgCarbHigh = stats.reduce(0.0) { $0 + $1.carbTargetHigh } / Double(count)

        return StatsSection(title: "Ernährung", systemImage: "leaf.fill") {
            Chart(stats) { s in
                BarMark(
                    x: .value("Tag", s.date, unit: .day),
                    y: .value("g KH", s.carbsIn)
                )
                .foregroundStyle(Color.blue.gradient)
                .cornerRadius(3)
            }
            .chartXAxis { periodAxis }
            .chartYAxis { countAxis }
            .frame(height: 160)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                MetricTile(title: "Kohlenh. gesamt", value: String(format: "%.0f g",  totalCarbs), icon: "leaf", color: .blue)
                MetricTile(title: "BE gesamt",       value: String(format: "%.1f BE", totalBE),    icon: "square.grid.2x2", color: .purple)
                MetricTile(title: "Ø KH/Tag",        value: String(format: "%.0f g",  totalCarbs / Double(count)), icon: "leaf", color: .blue)
                MetricTile(title: "Ø BE/Tag",        value: String(format: "%.1f BE", totalBE / Double(count)),    icon: "square.grid.2x2", color: .purple)
                MetricTile(title: "KH-Ref. min/Tag", value: String(format: "%.0f g", avgCarbLow),  icon: "target", color: .teal)
                MetricTile(title: "KH-Ref. max/Tag", value: String(format: "%.0f g", avgCarbHigh), icon: "target", color: .teal)
            }

            Text("Referenz aus geschätztem Gesamtverbrauch: Grundbedarf plus erfasste Aktivität.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Persönliche Rekorde (im Zeitraum)

    @ViewBuilder
    private var personalRecordsSection: some View {
        let list = workoutsInPeriod
        if !list.isEmpty {
            let longestDist = list.max(by: { $0.distanceKm < $1.distanceKm })
            let fastest     = list
                .filter { $0.distanceMeters > 500 }
                .max(by: { $0.averageSpeedMPS < $1.averageSpeedMPS })
            let longestTime = list.max(by: { $0.duration < $1.duration })
            let bestSteps   = stats.max(by: { $0.steps < $1.steps })
            let bestScore   = list.max(by: { $0.score(settings: settings).displayScore < $1.score(settings: settings).displayScore })

            StatsSection(title: "Rekorde im Zeitraum", systemImage: "trophy.fill") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    if let w = longestDist {
                        MetricTile(title: "Längste Distanz", value: formattedDistance(w.distanceKm), icon: "ruler", color: .green, subtitle: w.startDate.formatted(.dateTime.day().month(.abbreviated)))
                    }
                    if let w = fastest, w.averageSpeedKmh > 0 {
                        MetricTile(title: "Schnellstes Tempo", value: String(format: "%.1f km/h", w.averageSpeedKmh), icon: "bolt.fill", color: .yellow, subtitle: w.workoutType.displayName)
                    }
                    if let w = longestTime {
                        MetricTile(title: "Längstes Workout", value: formatDuration(w.duration), icon: "stopwatch", color: .teal, subtitle: w.workoutType.displayName)
                    }
                    if let d = bestSteps {
                        MetricTile(title: "Meiste Schritte", value: d.steps.formatted(), icon: "figure.walk", color: .blue, subtitle: d.date.formatted(.dateTime.day().month(.abbreviated)))
                    }
                    if let w = bestScore {
                        MetricTile(title: "Bester Score", value: "\(w.score(settings: settings).displayScore)", icon: "star.fill", color: .orange, subtitle: w.score(settings: settings).grade.rawValue)
                    }
                }
            }
        }
    }

    // MARK: - Consistency Heatmap (letzte 90 Tage)

    private var consistencyHeatmap: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let days: [Date] = (0..<90).reversed().compactMap {
            cal.date(byAdding: .day, value: -$0, to: today)
        }

        // Map day → intensity (0-1). Intensität = min(caloriesOut / 600, 1).
        let statsByDay = Dictionary(uniqueKeysWithValues: stats.map { (cal.startOfDay(for: $0.date), $0) })
        // Für 90 Tage brauchen wir ggf. Fallback aus healthKit.workouts.
        let workoutsByDay = Dictionary(grouping: healthKit.workouts) { cal.startOfDay(for: $0.startDate) }

        func intensity(_ d: Date) -> Double {
            if let s = statsByDay[d] { return min(s.caloriesOut / 600, 1) }
            let kcal = workoutsByDay[d]?.reduce(0.0) { $0 + $1.activeCalories } ?? 0
            return min(kcal / 600, 1)
        }

        let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 15)

        return StatsSection(title: "Konsistenz (90 Tage)", systemImage: "calendar") {
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(days, id: \.self) { d in
                    let i = intensity(d)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(heatColor(intensity: i))
                        .frame(height: 16)
                        .overlay(
                            cal.isDateInToday(d)
                                ? RoundedRectangle(cornerRadius: 3).stroke(Color.primary, lineWidth: 1)
                                : nil
                        )
                }
            }
            HStack(spacing: 6) {
                Text("weniger").font(.caption2).foregroundStyle(.secondary)
                ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { v in
                    RoundedRectangle(cornerRadius: 2).fill(heatColor(intensity: v)).frame(width: 14, height: 14)
                }
                Text("mehr").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
    }

    private func heatColor(intensity: Double) -> Color {
        if intensity <= 0.001 { return Color.gray.opacity(0.15) }
        return Color.orange.opacity(0.25 + intensity * 0.75)
    }

    // MARK: - Chart-Axis Helpers

    private var periodAxis: AxisMarks<some AxisMark> {
        AxisMarks(values: .stride(by: period.axisStride)) { _ in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
            AxisTick()
            AxisValueLabel(
                format: {
                    switch period {
                    case .today:           return Date.FormatStyle.dateTime.hour()
                    case .week:            return Date.FormatStyle.dateTime.weekday(.abbreviated)
                    case .month:           return Date.FormatStyle.dateTime.day().month(.abbreviated)
                    case .quarter, .year:  return Date.FormatStyle.dateTime.month(.abbreviated)
                    }
                }(),
                centered: true
            )
        }
    }

    private var countAxis: AxisMarks<some AxisMark> {
        AxisMarks { _ in
            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
            AxisValueLabel()
        }
    }

    // MARK: - Formatter

    private func formattedDistance(_ km: Double) -> String {
        settings.unitPreference == .metric
            ? String(format: "%.1f km", km)
            : String(format: "%.1f mi", km / 1.60934)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60
        return h > 0 ? "\(h) h \(m) min" : "\(m) min"
    }

    private func signedKcal(_ value: Double) -> String {
        let sign = value > 0 ? "+" : ""
        return "\(sign)\(String(format: "%.0f kcal", value))"
    }

    // MARK: - Data Loading

    /// Nur laden, wenn wir entweder nichts haben oder der letzte Ladevorgang
    /// älter als 30 s ist — hält das Wechseln zwischen Tabs flüssig.
    private func loadIfNeeded() async {
        if stats.isEmpty || lastLoadedAt == nil || Date().timeIntervalSince(lastLoadedAt!) > 30 {
            await load(force: false)
        }
    }

    private func load(force: Bool) async {
        if isLoading && !force { return }
        isLoading = true
        defer { isLoading = false }

        let days = period.days
        let raw  = await healthKit.fetchPeriodStats(days: days)
        let cal  = Calendar.current
        let profile = healthKit.profileSnapshot(settings: settings)
        let workoutsByDay = Dictionary(grouping: healthKit.workouts) {
            cal.startOfDay(for: $0.startDate)
        }

        let merged: [DayStat] = raw.map { dp in
            let day       = cal.startOfDay(for: dp.date)
            let wList     = workoutsByDay[day] ?? []
            let wKcal     = wList.reduce(0.0) { $0 + $1.activeCalories }
            let wKm       = wList.reduce(0.0) { $0 + $1.distanceKm }
            let activeKcal = max(dp.calories, wKcal)
            let baseline  = NutritionBaselineEstimator.estimate(for: day,
                                                                activeCalories: activeKcal,
                                                                profile: profile)
            let food      = foodLog.totals(on: day)
            return DayStat(
                date:         day,
                steps:        dp.steps,
                caloriesHK:   dp.calories,
                distanceKmHK: dp.distanceKm,
                kcalIn:       food.kcal,
                carbsIn:      food.carbs,
                workoutCount: wList.count,
                workoutKcal:  wKcal,
                workoutKm:    wKm,
                restingKcal:  baseline.restingCalories,
                carbTargetLow: baseline.carbReferenceLowGrams,
                carbTargetHigh: baseline.carbReferenceHighGrams
            )
        }

        stats = merged
        lastLoadedAt = Date()
    }
}

// MARK: - Sub-Components

/// Vereinheitlichtes Sektions-Layout: Kopfzeile + Card-Body.
struct StatsSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .padding(.horizontal)
            VStack(spacing: 12) {
                content()
            }
            .padding()
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal)
        }
    }
}

/// Kompakte Metrik-Kachel.
struct MetricTile: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.caption).foregroundStyle(.primary)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Text(value).font(.title3.bold()).foregroundStyle(color)
            if let s = subtitle {
                Text(s).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct EnergySnapshotCard: View {
    let title: String
    let intakeTitle: String
    let baselineTitle: String
    let movementTitle: String
    let totalTitle: String
    let baselineBalanceTitle: String
    let totalBalanceTitle: String
    let baselineCompareTitle: String
    let totalCompareTitle: String
    let hint: String
    let intakeKcal: Double
    let restingKcal: Double
    let activeKcal: Double
    let totalKcal: Double
    let baselineBalance: Double
    let totalBalance: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Label(title, systemImage: "flame.circle.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                BalanceChip(title: baselineBalanceTitle, value: baselineBalance)
            }

            HStack(spacing: 8) {
                EnergyMiniTile(title: intakeTitle, value: intakeKcal, icon: "fork.knife", color: .red)
                EnergyMiniTile(title: baselineTitle, value: restingKcal, icon: "bed.double.fill", color: .indigo)
                EnergyMiniTile(title: movementTitle, value: activeKcal, icon: "figure.walk.motion", color: .orange)
            }

            VStack(spacing: 10) {
                EnergyComparisonRow(
                    title: baselineCompareTitle,
                    consumed: intakeKcal,
                    target: restingKcal,
                    targetColor: .indigo
                )
                EnergyComparisonRow(
                    title: totalCompareTitle,
                    consumed: intakeKcal,
                    target: totalKcal,
                    targetColor: .orange
                )
            }

            HStack(spacing: 8) {
                BalanceChip(title: totalBalanceTitle, value: totalBalance)
                Spacer(minLength: 0)
                Label(kcalString(totalKcal), systemImage: "flame.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }

            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.indigo.opacity(0.10),
                            Color.orange.opacity(0.08),
                            Color.red.opacity(0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func kcalString(_ value: Double) -> String {
        String(format: "%.0f kcal", value)
    }
}

struct EnergyMiniTile: View {
    let title: String
    let value: Double
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(String(format: "%.0f", value))
                .font(.headline.monospacedDigit().bold())
                .foregroundStyle(color)
            Text("kcal")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.secondarySystemBackground).opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct EnergyComparisonRow: View {
    let title: String
    let consumed: Double
    let target: Double
    let targetColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(kcalString(consumed)) / \(kcalString(target))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                let maxValue = max(consumed, target, 1)
                let targetWidth = geo.size.width * min(target / maxValue, 1)
                let consumedWidth = geo.size.width * min(consumed / maxValue, 1)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.08))

                    RoundedRectangle(cornerRadius: 6)
                        .fill(targetColor.opacity(0.18))
                        .frame(width: max(10, targetWidth))

                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [Color.red.opacity(0.9), Color.orange.opacity(0.9)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(8, consumedWidth))
                }
            }
            .frame(height: 10)
        }
    }

    private func kcalString(_ value: Double) -> String {
        String(format: "%.0f kcal", value)
    }
}

struct BalanceChip: View {
    let title: String
    let value: Double

    private var color: Color { value > 0 ? .red : .green }
    private var icon: String { value > 0 ? "arrow.up.forward.circle.fill" : "arrow.down.forward.circle.fill" }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(signedKcal(value))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(color.opacity(0.10))
        .clipShape(Capsule())
    }

    private func signedKcal(_ value: Double) -> String {
        let sign = value > 0 ? "+" : ""
        return "\(sign)\(String(format: "%.0f kcal", value))"
    }
}

/// Zeile für heutiges Workout.
struct TodayWorkoutRow: View {
    let workout: WorkoutRecord
    let settings: UserSettings

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: workout.workoutType.systemImage)
                .font(.title3)
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .background(Color.secondary.opacity(0.15))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.workoutType.displayName).font(.subheadline.weight(.semibold))
                HStack(spacing: 6) {
                    Text(workout.startDate.formatted(date: .omitted, time: .shortened))
                    Text("·")
                    Text(formatDuration(workout.duration))
                    if workout.distanceMeters > 0 {
                        Text("·")
                        Text(workout.formattedDistance(unit: settings.unitPreference))
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if workout.activeCalories > 0 {
                Text(String(format: "%.0f kcal", workout.activeCalories))
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDuration(_ s: TimeInterval) -> String {
        let total = Int(s)
        let h = total / 3600, m = (total % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m) min"
    }
}

/// Balken pro Workout-Typ (Anzahl) mit Zusatzinfos.
struct WorkoutTypeBar: View {
    let type: WorkoutType
    let count: Int
    let km: Double
    let kcal: Double
    let fraction: Double
    let distanceLabel: String
    let formattedDistance: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(type.displayName, systemImage: type.systemImage)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(count)×")
                    .font(.subheadline.monospacedDigit().bold())
                    .foregroundStyle(.orange)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.orange.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.orange.gradient)
                        .frame(width: max(4, geo.size.width * fraction))
                }
            }
            .frame(height: 6)

            HStack(spacing: 8) {
                if km > 0 {
                    Text(formattedDistance).font(.caption2).foregroundStyle(.secondary)
                    Text("·").font(.caption2).foregroundStyle(.secondary)
                }
                Text(String(format: "%.0f kcal", kcal))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
