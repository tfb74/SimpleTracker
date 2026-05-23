import SwiftUI

struct ManualWorkoutEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(HealthKitService.self) private var healthKit
    @Environment(UserSettings.self) private var settings

    @State private var favoriteStore = WorkoutFavoriteStore.shared
    @State private var usageStore    = WorkoutUsageStore.shared

    // Aktivitätsauswahl
    @State private var selectedType: WorkoutType = .strength
    @State private var searchText = ""
    @State private var suggestedType: WorkoutType?
    @State private var isSuggesting = false
    @State private var suggestionTask: Task<Void, Never>?

    // Zeitpunkt & Dauer
    @State private var workoutDate = Date()
    @State private var durationHours = 0
    @State private var durationMinutes = 45

    // Intensität
    @State private var intensity: WorkoutIntensity = .medium

    // Kalorien (optional, sonst MET-Schätzung)
    @State private var caloriesEnabled = false
    @State private var calories = 300

    // Speichern
    @State private var isSaving = false
    @State private var saveError: String?

    private var durationSec: TimeInterval {
        TimeInterval(durationHours * 3600 + durationMinutes * 60)
    }

    private var estimatedCalories: Int {
        let profile = healthKit.profileSnapshot(settings: settings)
        let kcal = CaloricEstimator.estimate(
            type: selectedType,
            distanceMeters: 0,
            durationSec: durationSec,
            profile: profile,
            intensity: intensity
        )
        return max(0, Int(kcal.rounded()))
    }

    private var filteredTypes: [WorkoutType] {
        let lower = searchText.lowercased()
        let base = lower.isEmpty
            ? WorkoutType.allCases
            : WorkoutType.allCases.filter { $0.displayName.lowercased().contains(lower) }
        return usageStore.sortedByUsage(base)
    }

    private var favoriteTypes: [WorkoutType] {
        usageStore.sortedByUsage(WorkoutType.allCases.filter { favoriteStore.isFavorite($0) })
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Suche + LLM-Vorschlag
                Section {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField(lt("Suchen oder Aktivität eingeben…"), text: $searchText)
                            .textInputAutocapitalization(.sentences)
                            .onChange(of: searchText) { _, new in triggerSuggestion(new) }
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if isSuggesting {
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.75)
                            Text(lt("Passende Aktivität wird gesucht…"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else if let suggested = suggestedType, !searchText.isEmpty {
                        Button {
                            selectedType = suggested
                            UISelectionFeedbackGenerator().selectionChanged()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles").foregroundStyle(.purple)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(lt("LLM-Vorschlag"))
                                        .font(.caption2).foregroundStyle(.secondary)
                                    Text(suggested.displayName)
                                        .font(.subheadline).foregroundStyle(.primary)
                                }
                                Spacer()
                                Image(systemName: suggested == selectedType
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(suggested == selectedType ? Color.accentColor : Color.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(lt("Aktivität"))
                } footer: {
                    if WorkoutTypeSuggestionService.isAvailable {
                        Text(lt("Gib z. B. \"Beinpresse\" oder \"Zumba\" ein - das KI-Modell schlägt den passenden Typ vor."))
                    }
                }

                // MARK: Favoriten
                if !favoriteTypes.isEmpty && searchText.isEmpty {
                    Section(lt("Favoriten")) {
                        activityGrid(favoriteTypes)
                    }
                }

                // MARK: Alle / gefilterte Aktivitäten
                Section(searchText.isEmpty ? lt("Alle Aktivitäten") : lt("Ergebnisse")) {
                    if filteredTypes.isEmpty {
                        Text(lt("Keine Treffer"))
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        activityGrid(filteredTypes)
                    }
                }

                // MARK: Zeitpunkt, Dauer & Intensität
                Section(lt("Zeitpunkt & Dauer")) {
                    DatePicker(lt("Datum & Uhrzeit"), selection: $workoutDate)

                    HStack(spacing: 0) {
                        Picker(lt("Stunden"), selection: $durationHours) {
                            ForEach(0...23, id: \.self) { h in
                                Text(lf("%d Std", h)).tag(h)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)
                        .clipped()

                        Picker(lt("Minuten"), selection: $durationMinutes) {
                            ForEach(0...59, id: \.self) { m in
                                Text(lf("%d Min", m)).tag(m)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)
                        .clipped()
                    }
                    .frame(height: 150)
                    .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))

                    HStack {
                        Text(lt("Dauer"))
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        let h = durationHours, m = durationMinutes
                        if h > 0 && m > 0 {
                            Text(lf("%d Std %d Min", h, m)).font(.callout.bold())
                        } else if h > 0 {
                            Text(lf("%d Std", h)).font(.callout.bold())
                        } else {
                            Text(lf("%d Min", m)).font(.callout.bold())
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(lt("Intensität"))
                            .font(.caption).foregroundStyle(.secondary)
                        Picker(lt("Intensität"), selection: $intensity) {
                            ForEach(WorkoutIntensity.allCases) { level in
                                Label(level.rawValue, systemImage: level.systemImage)
                                    .tag(level)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.vertical, 4)
                }

                // MARK: Kalorien
                Section {
                    Toggle(lt("Kalorien manuell angeben"), isOn: $caloriesEnabled)
                    if caloriesEnabled {
                        Stepper(
                            lf("Kalorien: %d kcal", calories),
                            value: $calories, in: 0...5000, step: 10
                        )
                    }
                } header: {
                    Text(lt("Kalorien (optional)"))
                } footer: {
                    if caloriesEnabled {
                        Text(lt("Manuell eingegebene Kalorien werden direkt übernommen."))
                    } else if durationSec > 0 {
                        Text(lf("Schätzung für %@: ca. %d kcal.", selectedType.displayName, estimatedCalories))
                    } else {
                        Text(lt("Kalorien werden aus Aktivität, Dauer und Intensität geschätzt."))
                    }
                }

                if let err = saveError {
                    Section {
                        Text(err).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .navigationTitle(lt("Workout eintragen"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(lt("Abbrechen")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(lt("Speichern")) {
                        Task { await save() }
                    }
                    .fontWeight(.semibold)
                    .disabled(isSaving || durationSec <= 0)
                }
            }
            .overlay {
                if isSaving {
                    ProgressView(lt("Speichern…"))
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
            }
        }
    }

    // MARK: - Activity Grid

    private func activityGrid(_ types: [WorkoutType]) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 105), spacing: 8)],
            spacing: 8
        ) {
            ForEach(types) { type in
                WorkoutTypeChip(
                    type: type,
                    isSelected: selectedType == type,
                    isFavorite: favoriteStore.isFavorite(type)
                )
                .onTapGesture {
                    selectedType = type
                    UISelectionFeedbackGenerator().selectionChanged()
                }
                .contextMenu {
                    Button {
                        favoriteStore.toggle(type)
                    } label: {
                        Label(
                            favoriteStore.isFavorite(type) ? lt("Aus Favoriten entfernen") : lt("Als Favorit merken"),
                            systemImage: favoriteStore.isFavorite(type) ? "star.slash" : "star"
                        )
                    }
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
    }

    // MARK: - LLM Suggestion

    private func triggerSuggestion(_ text: String) {
        suggestionTask?.cancel()
        suggestedType = nil
        isSuggesting = false
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3, WorkoutTypeSuggestionService.isAvailable else { return }
        isSuggesting = true
        suggestionTask = Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            let t = await WorkoutTypeSuggestionService.suggest(for: trimmed)
            await MainActor.run {
                isSuggesting = false
                suggestedType = t
            }
        }
    }

    // MARK: - Save

    private func save() async {
        guard durationSec > 0 else { return }
        isSaving = true
        saveError = nil

        // Nutzung zählen — Picker sortiert beim nächsten Mal entsprechend
        usageStore.recordUsage(of: selectedType)

        let start = workoutDate
        let end = workoutDate.addingTimeInterval(durationSec)
        let cal = caloriesEnabled ? Double(calories) : Double(estimatedCalories)

        do {
            try await healthKit.saveWorkout(
                type: selectedType,
                start: start, end: end,
                steps: 0,
                calories: cal,
                distanceMeters: 0,
                routePoints: []
            )
            isSaving = false
            dismiss()
        } catch {
            isSaving = false
            saveError = lf("Speichern fehlgeschlagen: %@", error.localizedDescription)
        }
    }
}

// MARK: - WorkoutTypeChip

private struct WorkoutTypeChip: View {
    let type: WorkoutType
    let isSelected: Bool
    let isFavorite: Bool

    private var isLight: Bool { type.category == .light }
    private var accent: Color { isLight ? .teal : Color.accentColor }
    private var unselectedFg: Color { isLight ? .teal : .primary }
    private var unselectedBg: Color { isLight ? Color.teal.opacity(0.10) : Color(.secondarySystemBackground) }

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: type.systemImage)
                    .font(.title2)
                    .foregroundStyle(isSelected ? .white : unselectedFg)
                    .frame(maxWidth: .infinity)

                if isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                        .offset(x: 2, y: -2)
                }
            }
            Text(type.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? .white : unselectedFg)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 72)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(isSelected ? accent : unselectedBg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.clear : (isLight ? Color.teal.opacity(0.4) : Color.secondary.opacity(0.2)), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}
