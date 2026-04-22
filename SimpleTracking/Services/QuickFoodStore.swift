import Foundation

/// Holds built-in quick-select presets + any user-added custom presets
/// (persisted to UserDefaults as JSON).
@Observable
final class QuickFoodStore {
    static let shared = QuickFoodStore()

    private let defaultsKey = "QuickFoodStore.customPresets.v2"

    var customPresets: [QuickFoodPreset] = []

    /// Built-in drinks + any custom drinks the user has added.
    var drinks: [QuickFoodPreset] {
        QuickFoodPreset.builtInDrinks + customPresets.filter { $0.kind == .drink }
    }

    /// Built-in snacks/food + any custom snacks the user has added.
    var snacks: [QuickFoodPreset] {
        QuickFoodPreset.builtInSnacks + customPresets.filter { $0.kind == .food }
    }

    private init() {
        load()
    }

    // MARK: - Mutations

    func add(_ preset: QuickFoodPreset) {
        var p = preset
        p = QuickFoodPreset(
            id: UUID(),
            name: p.name,
            systemImage: p.systemImage,
            tintName: p.tintName,
            kind: p.kind,
            portionLabel: p.portionLabel,
            calories: p.calories,
            carbsGrams: p.carbsGrams,
            isBuiltIn: false
        )
        customPresets.append(p)
        save()
    }

    func remove(_ preset: QuickFoodPreset) {
        guard !preset.isBuiltIn else { return }
        customPresets.removeAll { $0.id == preset.id }
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return }
        if let decoded = try? JSONDecoder().decode([QuickFoodPreset].self, from: data) {
            customPresets = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(customPresets) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
