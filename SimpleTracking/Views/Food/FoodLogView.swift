import SwiftUI

struct FoodLogView: View {
    @Environment(FoodLogStore.self) private var store
    @State private var selectedDate = Date()
    @State private var showAddSheet = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                dateBar
                totalsCard
                entriesList
            }
            .appChrome(title: lt("Ernährung"), accent: .orange, metrics: headerMetrics) {
                Button { showAddSheet = true } label: {
                    AppChromeActionLabel(systemImage: "plus", tint: .orange)
                }
                .buttonStyle(.plain)
            }
            .sheet(isPresented: $showAddSheet) {
                AddFoodSheet(defaultDate: selectedDate)
            }
        }
    }

    private var headerMetrics: [AppHeaderMetric] {
        let totals = store.totals(on: selectedDate)

        return [
            AppHeaderMetric(
                title: lt("Kalorien"),
                value: String(format: "%.0f kcal", totals.kcal),
                systemImage: "flame.fill",
                tint: .orange
            ),
            AppHeaderMetric(
                title: "BE",
                value: String(format: "%.1f", totals.be),
                systemImage: "square.grid.2x2.fill",
                tint: .purple
            )
        ]
    }

    // MARK: - Date Selector

    private var dateBar: some View {
        HStack {
            Button { shift(days: -1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            DatePicker("Datum", selection: $selectedDate, displayedComponents: .date)
                .labelsHidden()
            Spacer()
            Button { shift(days: 1) } label: { Image(systemName: "chevron.right") }
                .disabled(Calendar.current.isDateInToday(selectedDate))
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func shift(days: Int) {
        if let d = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) {
            selectedDate = d
        }
    }

    // MARK: - Totals

    private var totalsCard: some View {
        let t = store.totals(on: selectedDate)
        return HStack(spacing: 14) {
            totalTile(title: "Kalorien", value: String(format: "%.0f", t.kcal), unit: "kcal", color: .orange, icon: "flame.fill")
            totalTile(title: "Kohlenhyd.", value: String(format: "%.0f", t.carbs), unit: "g", color: .blue, icon: "leaf.fill")
            totalTile(title: "BE", value: String(format: "%.1f", t.be), unit: "BE", color: .purple, icon: "square.grid.2x2.fill")
        }
        .padding(.horizontal)
        .padding(.bottom, 10)
    }

    private func totalTile(title: String, value: String, unit: String, color: Color, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(color)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.title3.bold()).minimumScaleFactor(0.7)
                Text(unit).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - List

    private var entriesList: some View {
        let entries = store.entries(on: selectedDate)
        return Group {
            if entries.isEmpty {
                ContentUnavailableView(
                    "Keine Einträge",
                    systemImage: "takeoutbag.and.cup.and.straw",
                    description: Text("Tippe auf + um ein Essen oder Getränk hinzuzufügen.")
                )
            } else {
                List {
                    ForEach(entries) { entry in
                        FoodEntryRow(entry: entry)
                    }
                    .onDelete { idx in
                        idx.map { entries[$0] }.forEach(store.remove)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }
}

struct FoodEntryRow: View {
    let entry: FoodEntry

    var body: some View {
        let nutrition = entry.resolvedNutrition

        HStack(spacing: 12) {
            Image(systemName: entry.kind.systemImage)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(.subheadline.bold())
                HStack(spacing: 6) {
                    Text(entry.timestamp, style: .time)
                    if let g = entry.portionGrams { Text("· \(Int(g)) g") }
                    if let ml = entry.portionMilliliters { Text("· \(Int(ml)) ml") }
                    Image(systemName: entry.source == .barcode ? "barcode.viewfinder"
                                    : entry.source == .photo ? "camera.fill" : "pencil")
                        .font(.caption2)
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(calorieLabel(for: nutrition)).font(.callout.bold())
                Text(String(format: "%.1f BE", nutrition.breadUnits))
                    .font(.caption2).foregroundStyle(.purple)
            }
        }
        .padding(.vertical, 2)
    }

    private func calorieLabel(for nutrition: FoodNutritionSnapshot) -> String {
        let prefix = nutrition.caloriesAreEstimated ? "≈ " : ""
        return "\(prefix)\(Int(nutrition.calories.rounded())) kcal"
    }
}
