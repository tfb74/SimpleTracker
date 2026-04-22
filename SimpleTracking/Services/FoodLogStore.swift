import Foundation

@Observable
final class FoodLogStore {
    static let shared = FoodLogStore()

    private(set) var entries: [FoodEntry] = []

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("food_log.json")
    }()

    private init() { load() }

    // MARK: - Queries

    func entries(on date: Date) -> [FoodEntry] {
        let cal = Calendar.current
        return entries
            .filter { cal.isDate($0.timestamp, inSameDayAs: date) }
            .sorted { $0.timestamp > $1.timestamp }
    }

    func totals(on date: Date) -> (kcal: Double, carbs: Double, be: Double) {
        let es = entries(on: date)
        let kcal  = es.reduce(0.0) { $0 + $1.resolvedCalories }
        let carbs = es.reduce(0.0) { $0 + $1.resolvedCarbsGrams }
        return (kcal, carbs, FoodEntry.breadUnits(fromCarbs: carbs))
    }

    // MARK: - Mutation
    //
    // Alle Mutationen schreiben parallel nach Apple Health, damit andere
    // Apps (Health, Waagen-Apps, Kalorienrechner usw.) die gleiche Sicht
    // auf Ernährung haben wie diese App. Die Health-Writes laufen
    // fire-and-forget im Hintergrund — lokale UI reagiert sofort.

    func add(_ entry: FoodEntry) {
        entries.append(entry)
        save()
        Task { [entry] in
            let ids = await HealthKitService.shared.writeFoodSamples(for: entry)
            guard !ids.isEmpty else { return }
            await MainActor.run {
                if let i = self.entries.firstIndex(where: { $0.id == entry.id }) {
                    self.entries[i].healthKitSampleIDs = ids
                    self.save()
                }
            }
        }
    }

    func update(_ entry: FoodEntry) {
        guard let i = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        let old = entries[i]
        entries[i] = entry
        save()
        // Einfacher Ansatz: alte Samples löschen, neue schreiben.
        Task { [old, entry] in
            await HealthKitService.shared.deleteFoodSamples(uuids: old.healthKitSampleIDs ?? [])
            let ids = await HealthKitService.shared.writeFoodSamples(for: entry)
            await MainActor.run {
                if let j = self.entries.firstIndex(where: { $0.id == entry.id }) {
                    self.entries[j].healthKitSampleIDs = ids
                    self.save()
                }
            }
        }
    }

    func remove(_ entry: FoodEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
        Task { [entry] in
            await HealthKitService.shared.deleteFoodSamples(uuids: entry.healthKitSampleIDs ?? [])
        }
    }

    func removeAll() {
        let snapshot = entries
        entries.removeAll()
        save()
        Task { [snapshot] in
            for e in snapshot {
                await HealthKitService.shared.deleteFoodSamples(uuids: e.healthKitSampleIDs ?? [])
            }
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([FoodEntry].self, from: data) else { return }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
