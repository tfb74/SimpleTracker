import Foundation
import UIKit
import Vision

#if canImport(FoundationModels)
import FoundationModels
#endif

struct RecognizedFoodItem: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var portionGrams: Int
    var calories: Int
    var carbsGrams: Int
}

/// Diagnostic information returned alongside the analysis result — useful for a
/// simulator self-test to verify each stage of the pipeline actually ran.
struct AnalysisDiagnostics {
    var visionLabels: [String] = []
    var visionMillis: Int = 0

    var llmRequested: Bool = false   // code path asked for LLM
    var llmAvailable: Bool = false   // SystemLanguageModel.default.isAvailable
    var llmUsed:      Bool = false   // LLM actually produced the items
    var llmMillis:    Int = 0
    var llmError:     String?

    var fallbackUsed: Bool = false   // heuristic kicked in
    var iOSVersion:   String = ""
    var itemCount:    Int = 0
}

enum FoodPhotoAnalyzerError: Error {
    case unavailable, invalidImage, modelFailed
}

/// Food photo analyzer. See `analyze(image:)` for the simple entry point and
/// `analyzeDetailed(image:)` for a diagnostic variant used by the self-test.
enum FoodPhotoAnalyzer {

    static var isLLMAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    // MARK: - Public Entries

    static func analyze(image: UIImage) async throws -> [RecognizedFoodItem] {
        let (items, _) = try await analyzeDetailed(image: image)
        return items
    }

    static func analyzeDetailed(image: UIImage,
                                labelHints: [String]? = nil) async throws -> ([RecognizedFoodItem], AnalysisDiagnostics) {
        var diag = AnalysisDiagnostics()
        diag.iOSVersion = UIDevice.current.systemVersion

        // Stage 1: Vision labels — or caller-supplied hints (e.g. simulator self-test).
        let labels: [String]
        let t0 = Date()
        if let labelHints, !labelHints.isEmpty {
            labels = labelHints
            diag.visionMillis = 0
        } else {
            do {
                labels = try await visionLabels(for: image)
                diag.visionMillis = Int(Date().timeIntervalSince(t0) * 1000)
            } catch {
                diag.llmError = "Vision: \(error.localizedDescription)"
                diag.visionMillis = Int(Date().timeIntervalSince(t0) * 1000)
                labels = []
            }
        }
        diag.visionLabels = labels

        // Stage 2: LLM (if available).
        diag.llmAvailable = isLLMAvailable
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), diag.llmAvailable, !labels.isEmpty {
            diag.llmRequested = true
            let t1 = Date()
            do {
                let llm = try await analyzeWithLLM(labels: labels)
                diag.llmMillis = Int(Date().timeIntervalSince(t1) * 1000)
                if !llm.isEmpty {
                    diag.llmUsed = true
                    diag.itemCount = llm.count
                    return (llm, diag)
                }
            } catch {
                diag.llmError = String(describing: error)
                diag.llmMillis = Int(Date().timeIntervalSince(t1) * 1000)
            }
        }
        #endif

        // Stage 3: heuristic fallback.
        diag.fallbackUsed = true
        let items = heuristicItems(from: labels)
        diag.itemCount = items.count
        return (items, diag)
    }

    // MARK: - Foundation Models (text-only, fed by Vision labels)

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func analyzeWithLLM(labels: [String]) async throws -> [RecognizedFoodItem] {
        // Zwei unabhängige Interpretationen, um die bekannte „zu freundliche"
        // Schätzung zu kompensieren. Pro Item wird der jeweils höhere Wert
        // übernommen (Portion, Kalorien, Kohlenhydrate).
        async let passA = llmPass(labels: labels, style: .realistic)
        async let passB = llmPass(labels: labels, style: .generous)

        let (a, b) = try await (passA, passB)
        return mergeBlended(realistic: a, generous: b)
    }

    private enum LLMStyle { case realistic, generous }

    @available(iOS 26.0, *)
    private static func llmPass(labels: [String], style: LLMStyle) async throws -> [RecognizedFoodItem] {
        let toneLine: String
        switch style {
        case .realistic:
            toneLine = "Schätze realistische Durchschnittswerte — eher am oberen Rand des üblichen Bereichs, nicht zu niedrig."
        case .generous:
            toneLine = "Gehe von einer typischen Restaurant- bzw. sättigenden Portion aus. Unterschätze Kalorien und Portionsgrößen nicht — Fette, Öle, Saucen und Beilagen großzügig einrechnen."
        }

        let instructions = """
        Du bist ein Ernährungsassistent. Der Nutzer gibt dir eine Liste erkannter Bildlabels
        (aus einer Bilderkennung) von einem Foto von Essen oder Getränken.
        Leite daraus die wahrscheinlichsten Speisen oder Getränke ab und schätze für jede:
        - den Namen auf Deutsch
        - die typische Portionsgröße in Gramm
        - die Kalorien der Portion
        - die Kohlenhydrate der Portion in Gramm

        WICHTIG — mehrteilige Gerichte erkennen:
        Viele Gerichte haben Bestandteile, die auf dem Foto verdeckt sind oder nur zum
        Teil sichtbar. Denke aktiv darüber nach, was unter oder neben den sichtbaren
        Zutaten typischerweise liegt. Liste JEDEN plausiblen Bestandteil als
        EIGENES Item auf — nicht nur das Offensichtliche.

        Typische DACH-Kombinationen:
        - Käse/Wurst/Salami/Schinken sichtbar → mit sehr hoher Wahrscheinlichkeit
          liegt darunter Brot, Brötchen, Semmel oder Toast. Beide getrennt auflisten.
        - Salat/Käse/Sauce sichtbar → oft auf einem Burger-Bun, Fladenbrot oder Wrap.
        - Sauce/Hackfleisch → meist mit Nudeln, Reis oder Kartoffeln als Beilage.
        - Pommes/Chips sichtbar → oft mit Burger, Steak, Schnitzel o. Ä. kombiniert.
        - Ei auf Brot/Brötchen → Ei UND Brot separat.
        - Sandwich-Optik → Brot + Füllungen getrennt auflisten.

        Wenn du unsicher bist, ob ein Bestandteil da ist: im Zweifel LIEBER auflisten.
        Eine fehlende Komponente ist schlimmer als eine zu viele, weil der Nutzer
        sie leicht löschen kann.

        \(toneLine)
        Ignoriere Labels, die keine Lebensmittel oder Getränke sind (Teller,
        Besteck, Tisch, Schüssel usw.).
        Antworte ausschließlich mit dem geforderten strukturierten Ergebnis.
        """

        let joined = labels.joined(separator: ", ")
        let session = LanguageModelSession(instructions: instructions)

        let response = try await session.respond(
            to: """
            Erkannte Labels: \(joined).
            Welche Speisen oder Getränke sind das? Denke auch an wahrscheinliche
            verdeckte Bestandteile (z. B. Brot/Brötchen unter Belag, Beilagen
            neben dem Hauptgericht). Schätze Portion und Nährwerte für JEDES
            einzelne Item.
            """,
            generating: LLMFoodResponse.self
        )

        return response.content.items.map {
            RecognizedFoodItem(
                name: $0.name,
                portionGrams: $0.portionGrams,
                calories: $0.calories,
                carbsGrams: $0.carbsGrams
            )
        }
    }

    /// Blend-Faktor gegenüber der realistischen Schätzung:
    /// 0.0 = reine realistische Schätzung (kein Boost),
    /// 1.0 = Maximum aus beiden Pässen (volle ~30% Überhöhung).
    /// Der Nutzer hat sich für +15% entschieden → 0.5 halbiert den Boost.
    private static let generousBlend: Double = 0.5

    /// Kombiniert zwei LLM-Durchläufe: realistische Basis + anteiliger
    /// „Generous-Zuschlag". Pro Item wird jedes Nährwert-Feld mit
    /// `realistic + generousBlend * max(0, generous - realistic)` gemischt.
    private static func mergeBlended(realistic a: [RecognizedFoodItem],
                                     generous  b: [RecognizedFoodItem]) -> [RecognizedFoodItem] {
        if a.isEmpty { return b }
        if b.isEmpty { return a }

        func blend(_ realistic: Int, _ generous: Int) -> Int {
            let diff = max(0, generous - realistic)
            return realistic + Int((Double(diff) * generousBlend).rounded())
        }

        return a.enumerated().map { idx, item in
            let match = b.first(where: { $0.name.lowercased() == item.name.lowercased() })
                     ?? (idx < b.count ? b[idx] : nil)
            guard let m = match else { return item }
            return RecognizedFoodItem(
                name: item.name,
                portionGrams: blend(item.portionGrams, m.portionGrams),
                calories:     blend(item.calories,     m.calories),
                carbsGrams:   blend(item.carbsGrams,   m.carbsGrams)
            )
        }
    }

    @available(iOS 26.0, *)
    @Generable
    fileprivate struct LLMFoodResponse {
        @Guide(description: "Liste aller erkannten Lebensmittel oder Getränke.")
        let items: [LLMFoodItem]
    }

    @available(iOS 26.0, *)
    @Generable
    fileprivate struct LLMFoodItem {
        @Guide(description: "Name auf Deutsch, z. B. 'Spaghetti Bolognese' oder 'Apfelschorle'.")
        let name: String
        @Guide(description: "Geschätzte Portionsgröße in Gramm.")
        let portionGrams: Int
        @Guide(description: "Geschätzte Kalorien der Portion.")
        let calories: Int
        @Guide(description: "Geschätzte Kohlenhydrate der Portion in Gramm.")
        let carbsGrams: Int
    }
    #endif

    // MARK: - Vision

    private static func visionLabels(for image: UIImage) async throws -> [String] {
        guard let cgImage = image.cgImage else { throw FoodPhotoAnalyzerError.invalidImage }

        // Single-resume guard: Vision's completion handler may fire AND `perform`
        // may also throw for the same failure, causing a continuation misuse.
        final class Resumer { var done = false }
        let state = Resumer()

        return try await withCheckedThrowingContinuation { cont in
            let request = VNClassifyImageRequest { req, err in
                guard !state.done else { return }
                state.done = true
                if let err { cont.resume(throwing: err); return }
                let observations = (req.results as? [VNClassificationObservation]) ?? []
                // Niedrigere Confidence-Schwelle + mehr Kandidaten → das LLM sieht
                // auch Hinweise auf verdeckte Komponenten (Brötchen unter Käse,
                // Salami unter Käse, Salat unter Dressing, …). Hier lieber etwas
                // zu freigiebig sein, die LLM-Stufe filtert irrelevante Labels
                // anschließend selbst aus.
                let top = observations
                    .filter { $0.confidence > 0.08 }
                    .prefix(20)
                    .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
                cont.resume(returning: Array(top))
            }
            do {
                try VNImageRequestHandler(cgImage: cgImage).perform([request])
            } catch {
                guard !state.done else { return }
                state.done = true
                cont.resume(throwing: error)
            }
        }
    }

    // MARK: - Heuristic Fallback

    private static func heuristicItems(from labels: [String]) -> [RecognizedFoodItem] {
        labels.map { label in
            let guess = nutritionGuess(for: label)
            return RecognizedFoodItem(
                name: label.capitalized,
                portionGrams: guess.grams,
                calories: guess.kcal,
                carbsGrams: guess.carbs
            )
        }
    }

    private static func nutritionGuess(for label: String) -> (grams: Int, kcal: Int, carbs: Int) {
        // Werte bewusst am oberen Rand üblicher Portionen — Fette, Saucen und
        // Beilagen werden mit einkalkuliert, damit Schätzungen nicht zu niedrig
        // ausfallen.
        let l = label.lowercased()
        if l.contains("pizza")    { return (250, 720, 80) }
        if l.contains("burger")   { return (260, 760, 55) }
        if l.contains("salad")    { return (250, 220, 15) }
        if l.contains("pasta")    { return (300, 520, 80) }
        if l.contains("bread")    { return (60, 170, 30) }
        if l.contains("apple")    { return (180, 100, 26) }
        if l.contains("banana")   { return (120, 110, 28) }
        if l.contains("coffee")   { return (200, 15, 2) }
        if l.contains("beer")     { return (500, 250, 22) }
        if l.contains("wine")     { return (150, 135, 5) }
        if l.contains("water")    { return (300, 0, 0) }
        if l.contains("rice")     { return (250, 340, 70) }
        if l.contains("fries")    { return (180, 560, 65) }
        return (200, 320, 35) // neutral fallback (etwas großzügiger)
    }
}
