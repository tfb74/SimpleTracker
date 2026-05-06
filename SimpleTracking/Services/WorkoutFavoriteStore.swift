import Foundation

/// Verwaltet favorisierte Workout-Typen persistent in UserDefaults.
@Observable
final class WorkoutFavoriteStore {
    static let shared = WorkoutFavoriteStore()

    private let key = "WorkoutFavoriteStore.favorites"
    private(set) var favorites: Set<String> = []

    private init() {
        if let stored = UserDefaults.standard.stringArray(forKey: key) {
            favorites = Set(stored)
        }
    }

    func isFavorite(_ type: WorkoutType) -> Bool {
        favorites.contains(type.rawValue)
    }

    func toggle(_ type: WorkoutType) {
        if favorites.contains(type.rawValue) {
            favorites.remove(type.rawValue)
        } else {
            favorites.insert(type.rawValue)
        }
        UserDefaults.standard.set(Array(favorites), forKey: key)
    }
}
