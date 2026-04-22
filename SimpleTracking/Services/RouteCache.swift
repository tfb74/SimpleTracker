import Foundation

/// Local JSON-file cache for workout routes.
/// Keyed by HKWorkout UUID string → array of RoutePoints.
/// Bypasses HKWorkoutRouteBuilder, which is unreliable in the iOS Simulator.
final class RouteCache {
    static let shared = RouteCache()

    private let fileURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("route_cache.json")
    }()

    private let lock = NSLock()
    private var store: [String: [RoutePoint]] = [:]

    private init() { load() }

    func setRoute(_ points: [RoutePoint], forKey key: String) {
        lock.lock()
        store[key] = points
        lock.unlock()
        persist()
        print("[RouteCache] stored \(points.count) points for key=\(key). total entries=\(store.count)")
    }

    func route(forKey key: String) -> [RoutePoint]? {
        lock.lock()
        defer { lock.unlock() }
        guard let pts = store[key], !pts.isEmpty else { return nil }
        return pts
    }

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return store.count
    }

    func removeAll() {
        lock.lock()
        store = [:]
        lock.unlock()
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: [RoutePoint]].self, from: data)
        else { return }
        lock.lock()
        store = decoded
        lock.unlock()
    }

    private func persist() {
        lock.lock()
        let snapshot = store
        lock.unlock()
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
