import Foundation

@Observable
final class LocalAchievementStore {
    static let shared = LocalAchievementStore()

    private let storageKey = "localAchievements.v1"

    /// Maps raw achievement identifier → unlock date.
    private(set) var unlocks: [String: Date] = [:]

    var unlockedIdentifiers: Set<String> { Set(unlocks.keys) }

    private init() { load() }

    // MARK: - Unlock / Query

    @discardableResult
    func unlock(_ id: String, at date: Date = Date()) -> Bool {
        guard unlocks[id] == nil else { return false }
        unlocks[id] = date
        save()
        return true
    }

    func isUnlocked(_ id: String) -> Bool { unlocks[id] != nil }

    func removeAll() {
        unlocks.removeAll()
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: Date].self, from: data) else { return }
        unlocks = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(unlocks) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
