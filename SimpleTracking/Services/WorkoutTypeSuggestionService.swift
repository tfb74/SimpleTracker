import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Ordnet eine freitext-Aktivitätsbeschreibung dem passendsten WorkoutType zu.
enum WorkoutTypeSuggestionService {

    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    static func suggest(for text: String) async -> WorkoutType? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return nil }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return try? await suggestWithLLM(trimmed)
        }
        #endif
        return nil
    }

    // MARK: - Foundation Models

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func suggestWithLLM(_ text: String) async throws -> WorkoutType? {
        let typeList = WorkoutType.allCases
            .map { "\($0.rawValue) (\($0.displayName))" }
            .joined(separator: ", ")

        let instructions = """
        Du ordnest Workout- oder Aktivitätsbeschreibungen dem am besten passenden
        vordefinierten Typ zu.
        Verfügbare Typen: \(typeList).
        Antworte NUR mit dem rawValue des passendsten Typs (z.B. "strength").
        Keine anderen Zeichen, keine Erklärungen.
        """

        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(
            to: "Aktivität: \(text)",
            generating: LLMTypeResponse.self
        )

        let raw = response.content.workoutTypeRawValue
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return WorkoutType(rawValue: raw)
    }

    @available(iOS 26.0, *)
    @Generable
    fileprivate struct LLMTypeResponse {
        @Guide(description: "rawValue des passendsten WorkoutType, z.B. 'strength', 'running', 'yoga'.")
        let workoutTypeRawValue: String
    }
    #endif
}
