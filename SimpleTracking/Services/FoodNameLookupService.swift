import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Schlägt Nährwerte für einen eingegebenen Lebensmittelnamen vor,
/// indem das On-Device-LLM (Apple Intelligence) befragt wird.
enum FoodNameLookupService {

    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    /// Gibt einen Nährwert-Vorschlag für den übergebenen Namen zurück,
    /// oder `nil`, wenn das LLM nicht verfügbar ist oder keine sinnvolle
    /// Antwort liefert.
    static func lookup(name: String) async -> RecognizedFoodItem? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return nil }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return try? await lookupWithLLM(trimmed)
        }
        #endif
        return nil
    }

    // MARK: - Foundation Models

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func lookupWithLLM(_ name: String) async throws -> RecognizedFoodItem? {
        let instructions = """
        Du bist ein Ernährungsassistent für den deutschsprachigen Raum (DACH).
        Der Nutzer nennt ein Lebensmittel oder ein Gericht. Schätze für eine typische
        Haushaltsportion realistische Durchschnittswerte:
        - Portionsgröße in Gramm (bei Getränken in ml, ebenfalls als Integer angeben)
        - Kalorien der Portion (kcal)
        - Kohlenhydrate der Portion in Gramm

        Berücksichtige typische Zubereitungsarten und Beilagen, z.B.:
        - Spaghetti Bolognese = Nudeln + Sauce + Fleisch
        - Gänsebraten = Fleisch mit typischem Fettanteil, ohne Beilagen
        - Schnitzel = mit typischer Panade, ohne Beilage
        Antworte nur mit dem strukturierten Ergebnis, keine Erklärungen.
        """

        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(
            to: "Lebensmittel: \(name). Schätze Portion und Nährwerte.",
            generating: LLMFoodLookupResponse.self
        )
        let item = response.content
        guard item.calories > 0 else { return nil }
        return RecognizedFoodItem(
            name: name,
            portionGrams: max(1, item.portionGrams),
            calories: item.calories,
            carbsGrams: item.carbsGrams
        )
    }

    @available(iOS 26.0, *)
    @Generable
    fileprivate struct LLMFoodLookupResponse {
        @Guide(description: "Portionsgröße in Gramm oder ml, als ganze Zahl.")
        let portionGrams: Int
        @Guide(description: "Kalorien der Portion in kcal, als ganze Zahl.")
        let calories: Int
        @Guide(description: "Kohlenhydrate der Portion in Gramm, als ganze Zahl.")
        let carbsGrams: Int
    }
    #endif
}
