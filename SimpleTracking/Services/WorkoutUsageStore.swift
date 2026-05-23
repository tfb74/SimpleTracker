import Foundation

/// Zählt wie oft jeder Workout-Typ gestartet wurde, persistiert in UserDefaults.
/// Wird vom Picker genutzt, um Aktivitäten nach Häufigkeit zu sortieren —
/// häufig genutzte Sportarten erscheinen zuerst.
@Observable
final class WorkoutUsageStore {
    static let shared = WorkoutUsageStore()

    private let key = "WorkoutUsageStore.counts.v1"
    private(set) var counts: [String: Int] = [:]

    private init() {
        if let stored = UserDefaults.standard.dictionary(forKey: key) as? [String: Int] {
            counts = stored
        }
    }

    /// Zählt eine Nutzung des angegebenen Typs hoch.
    func recordUsage(of type: WorkoutType) {
        counts[type.rawValue, default: 0] += 1
        save()
    }

    func count(for type: WorkoutType) -> Int {
        counts[type.rawValue] ?? 0
    }

    /// Sortiert eine Liste von WorkoutTypes: häufiger genutzt zuerst,
    /// bei Gleichstand alphabetisch nach Anzeigename.
    func sortedByUsage(_ types: [WorkoutType]) -> [WorkoutType] {
        types.sorted { a, b in
            let ca = count(for: a)
            let cb = count(for: b)
            if ca != cb { return ca > cb }
            return a.displayName.localizedCompare(b.displayName) == .orderedAscending
        }
    }

    private func save() {
        UserDefaults.standard.set(counts, forKey: key)
    }
}
