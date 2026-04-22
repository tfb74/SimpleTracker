import SwiftUI

struct ManualFoodEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(FoodLogStore.self) private var store
    @State private var quickStore = QuickFoodStore.shared

    let defaultDate: Date
    let onComplete: () -> Void

    enum Metric: String, CaseIterable, Identifiable {
        case calories = "Kalorien"
        case carbs    = "Kohlenhydrate"
        case be       = "BE"
        var id: String { rawValue }

        var unit: String {
            switch self {
            case .calories: "kcal"
            case .carbs:    "g"
            case .be:       "BE"
            }
        }
        var tint: Color {
            switch self {
            case .calories: .orange
            case .carbs:    .blue
            case .be:       .purple
            }
        }
    }

    @State private var timestamp: Date
    @State private var name = ""
    @State private var kind: FoodKind = .food
    @State private var metric: Metric = .calories
    @State private var amount: Int = 100

    // Quick-Select
    @State private var showQuickSelect = false
    @State private var quickCategory: FoodKind = .drink
    @State private var showAddPreset = false
    @State private var presetBeingDeleted: QuickFoodPreset?

    init(defaultDate: Date, draft: RecognizedFoodItem? = nil, onComplete: @escaping () -> Void) {
        self.defaultDate = defaultDate
        self.onComplete = onComplete
        let cal = Calendar.current.isDateInToday(defaultDate) ? Date() : defaultDate
        _timestamp = State(initialValue: cal)
        if let draft {
            _name = State(initialValue: draft.name)
            if draft.calories > 0 {
                _metric = State(initialValue: .calories)
                _amount = State(initialValue: Self.clamp(draft.calories))
            } else if draft.carbsGrams > 0 {
                _metric = State(initialValue: .carbs)
                _amount = State(initialValue: Self.clamp(draft.carbsGrams))
            }
        }
    }

    private static func clamp(_ v: Int) -> Int { min(max(v, 1), 999) }

    private var nutritionPreview: FoodNutritionSnapshot {
        switch metric {
        case .calories:
            return FoodNutritionSnapshot(
                calories: Double(amount),
                carbsGrams: 0,
                caloriesAreEstimated: false
            )
        case .carbs:
            let carbs = Double(amount)
            return FoodNutritionSnapshot(
                calories: FoodEntry.estimatedCalories(fromCarbs: carbs),
                carbsGrams: carbs,
                caloriesAreEstimated: true
            )
        case .be:
            let carbs = FoodEntry.carbs(fromBreadUnits: Double(amount))
            return FoodNutritionSnapshot(
                calories: FoodEntry.estimatedCalories(fromCarbs: carbs),
                carbsGrams: carbs,
                caloriesAreEstimated: true
            )
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Quick-Select — collapsible, tap header to expand
                Section {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showQuickSelect.toggle()
                        }
                    } label: {
                        HStack {
                            Label("Quick-Auswahl", systemImage: "bolt.fill")
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(showQuickSelect ? "schließen" : "öffnen")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(showQuickSelect ? 180 : 0))
                        }
                        .contentShape(Rectangle())
                    }

                    if showQuickSelect {
                        Picker("Kategorie", selection: $quickCategory) {
                            Label("Getränke",  systemImage: "cup.and.saucer.fill").tag(FoodKind.drink)
                            Label("Snacks",    systemImage: "fork.knife").tag(FoodKind.food)
                        }
                        .pickerStyle(.segmented)

                        let presets = quickCategory == .drink ? quickStore.drinks : quickStore.snacks
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 110), spacing: 8)],
                            spacing: 8
                        ) {
                            ForEach(presets) { preset in
                                QuickPresetChip(preset: preset)
                                    .onTapGesture { quickAdd(preset) }
                                    .onLongPressGesture {
                                        if !preset.isBuiltIn { presetBeingDeleted = preset }
                                    }
                            }
                            // Add-button tile
                            Button { showAddPreset = true } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.title2)
                                    Text("Eigenes")
                                        .font(.caption2.weight(.semibold))
                                }
                                .frame(maxWidth: .infinity, minHeight: 72)
                                .foregroundStyle(Color.accentColor)
                                .background(Color.accentColor.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    }
                } footer: {
                    if showQuickSelect {
                        Text("Tippen = sofort hinzufügen. Lang drücken = eigenen Preset löschen. Eingebaute Presets können nicht gelöscht werden.")
                    }
                }

                // MARK: Manual entry
                Section("Zeitpunkt & Art") {
                    DatePicker("Zeit", selection: $timestamp)
                    Picker("Art", selection: $kind) {
                        ForEach(FoodKind.allCases, id: \.self) {
                            Label($0.displayName, systemImage: $0.systemImage).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Name") {
                    TextField("z. B. Vollkornbrot", text: $name)
                        .textInputAutocapitalization(.sentences)
                }

                Section {
                    HStack(spacing: 0) {
                        Picker("Metrik", selection: $metric) {
                            ForEach(Metric.allCases) { m in
                                Text(m.rawValue).tag(m)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)
                        .clipped()

                        Picker("Wert", selection: $amount) {
                            ForEach(1...999, id: \.self) { n in
                                Text("\(n)").tag(n)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)
                        .clipped()
                    }
                    .frame(height: 170)
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))

                    HStack {
                        Text("Auswahl")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(amount) \(metric.unit)")
                            .font(.callout.bold())
                            .foregroundStyle(metric.tint)
                        if metric == .be {
                            Text("≈ \(amount * 12) g")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if metric == .carbs {
                            Text(String(format: "≈ %.1f BE", Double(amount) / 12.0))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Abgeleitete Werte")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            derivedMetricPill(
                                title: "Kalorien",
                                value: caloriePreviewLabel,
                                color: .orange
                            )
                            derivedMetricPill(
                                title: "Kohlenhydrate",
                                value: String(format: "%.0f g", nutritionPreview.carbsGrams),
                                color: .blue
                            )
                            derivedMetricPill(
                                title: "BE",
                                value: String(format: "%.1f BE", nutritionPreview.breadUnits),
                                color: .purple
                            )
                        }
                    }
                } header: {
                    Text("Wert")
                } footer: {
                    Text("Wähle links, ob du Kalorien, Kohlenhydrate oder Broteinheiten eingibst. 1 BE = 12 g Kohlenhydrate. Wenn KH oder BE vorliegen, werden Kalorien mit 4 kcal pro g KH geschätzt.")
                }
            }
            .navigationTitle("Manuell")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Speichern") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showAddPreset) {
                AddQuickPresetView()
            }
            .confirmationDialog(
                presetBeingDeleted.map { "„\($0.name)" + "“ löschen?" } ?? "",
                isPresented: Binding(get: { presetBeingDeleted != nil },
                                     set: { if !$0 { presetBeingDeleted = nil } }),
                titleVisibility: .visible
            ) {
                Button("Löschen", role: .destructive) {
                    if let p = presetBeingDeleted { quickStore.remove(p) }
                    presetBeingDeleted = nil
                }
                Button("Abbrechen", role: .cancel) { presetBeingDeleted = nil }
            }
        }
    }

    // MARK: - Quick add

    private func quickAdd(_ preset: QuickFoodPreset) {
        let entry = FoodEntry(
            timestamp: Calendar.current.isDateInToday(defaultDate) ? Date() : defaultDate,
            name: preset.name,
            kind: preset.kind,
            portionGrams: preset.kind == .food ? Self.parseGrams(preset.portionLabel) : nil,
            portionMilliliters: preset.kind == .drink ? Self.parseMl(preset.portionLabel) : nil,
            calories: preset.calories,
            carbsGrams: preset.carbsGrams,
            source: .manual
        )
        store.add(entry)
        UISelectionFeedbackGenerator().selectionChanged()
        dismiss()
        onComplete()
    }

    private static func parseGrams(_ label: String) -> Double? {
        let l = label.lowercased()
        guard l.contains("g") else { return nil }
        return Double(l.components(separatedBy: CharacterSet(charactersIn: "0123456789").inverted).joined())
    }
    private static func parseMl(_ label: String) -> Double? {
        let l = label.lowercased()
        guard l.contains("ml") else { return nil }
        return Double(l.components(separatedBy: CharacterSet(charactersIn: "0123456789").inverted).joined())
    }

    // MARK: - Manual save

    private func save() {
        let calories: Double
        let carbs: Double
        switch metric {
        case .calories:
            calories = Double(amount)
            carbs = 0
        case .carbs:
            carbs = Double(amount)
            calories = FoodEntry.estimatedCalories(fromCarbs: carbs)
        case .be:
            carbs = FoodEntry.carbs(fromBreadUnits: Double(amount))
            calories = FoodEntry.estimatedCalories(fromCarbs: carbs)
        }

        let entry = FoodEntry(
            timestamp: timestamp,
            name: name.trimmingCharacters(in: .whitespaces),
            kind: kind,
            portionGrams: nil,
            portionMilliliters: nil,
            calories: calories,
            carbsGrams: carbs,
            source: .manual
        )
        store.add(entry)
        dismiss()
        onComplete()
    }

    private var caloriePreviewLabel: String {
        let prefix = nutritionPreview.caloriesAreEstimated ? "≈ " : ""
        return "\(prefix)\(Int(nutritionPreview.calories.rounded())) kcal"
    }

    private func derivedMetricPill(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Chip View

/// Gleicher Stil wie `MetricTile` in der Statistik-Übersicht:
/// kleines Symbol + Titel oben, großer farbiger Wert darunter, Subtitle in grau.
private struct QuickPresetChip: View {
    let preset: QuickFoodPreset

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: preset.systemImage)
                    .font(.caption)
                    .foregroundStyle(.primary)
                Text(preset.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text("\(Int(preset.calories)) kcal")
                .font(.title3.bold())
                .foregroundStyle(.primary)
            HStack(spacing: 4) {
                Text(preset.portionLabel)
                if preset.carbsGrams > 0 {
                    Text("·")
                    Text("\(Int(preset.carbsGrams)) g KH")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(preset.isBuiltIn ? Color.clear : Color.accentColor.opacity(0.4), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Add-preset sheet

private struct AddQuickPresetView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var quickStore = QuickFoodStore.shared

    @State private var name = ""
    @State private var symbol = "fork.knife"
    @State private var tintName = "orange"
    @State private var kind: FoodKind = .food
    @State private var portion = ""
    @State private var kcal = 200
    @State private var carbs = 25

    var body: some View {
        NavigationStack {
            Form {
                Section("Allgemein") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.sentences)
                    Picker("Art", selection: $kind) {
                        Label("Essen", systemImage: "fork.knife").tag(FoodKind.food)
                        Label("Getränk", systemImage: "cup.and.saucer.fill").tag(FoodKind.drink)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: kind) { _, new in
                        // Keep symbol sane when category changes
                        let choices = new == .drink
                            ? QuickFoodPreset.customSymbolChoicesDrink
                            : QuickFoodPreset.customSymbolChoicesFood
                        if !choices.contains(symbol) { symbol = choices.first ?? "fork.knife" }
                    }
                    TextField("Portion (z. B. 250 ml oder 60 g)", text: $portion)
                }

                Section("Symbol") {
                    let choices = kind == .drink
                        ? QuickFoodPreset.customSymbolChoicesDrink
                        : QuickFoodPreset.customSymbolChoicesFood
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 6) {
                        ForEach(choices, id: \.self) { s in
                            Image(systemName: s)
                                .font(.title3)
                                .foregroundStyle(s == symbol ? Color.accentColor : .secondary)
                                .frame(width: 44, height: 44)
                                .background(s == symbol ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .onTapGesture { symbol = s }
                        }
                    }
                }

                Section("Nährwerte pro Portion") {
                    Stepper("Kalorien: \(kcal) kcal", value: $kcal, in: 0...2000, step: 5)
                    Stepper("Kohlenhydrate: \(carbs) g", value: $carbs, in: 0...300, step: 1)
                    Text(String(format: "≈ %.1f BE", Double(carbs) / 12.0))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Preset hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Hinzufügen") {
                        let p = QuickFoodPreset(
                            name: name.trimmingCharacters(in: .whitespaces),
                            systemImage: symbol,
                            tintName: tintName,
                            kind: kind,
                            portionLabel: portion.trimmingCharacters(in: .whitespaces),
                            calories: Double(kcal),
                            carbsGrams: Double(carbs),
                            isBuiltIn: false
                        )
                        quickStore.add(p)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
