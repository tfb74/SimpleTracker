import Foundation

@Observable
final class WorkoutDraftStore {
    static let shared = WorkoutDraftStore()

    private(set) var currentDraft: WorkoutDraft?

    private let fileURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("workout_draft.json")
    }()

    private init() {
        load()
    }

    func save(_ draft: WorkoutDraft) {
        currentDraft = draft
        persist()
    }

    func clear() {
        currentDraft = nil
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(WorkoutDraft.self, from: data) else { return }
        currentDraft = decoded
    }

    private func persist() {
        guard let currentDraft,
              let data = try? JSONEncoder().encode(currentDraft) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
