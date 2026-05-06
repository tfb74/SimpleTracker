import Foundation
import UIKit
import Vision
import CoreGraphics

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

struct AnalysisDiagnostics {
    var visionLabels: [String] = []
    var visionMillis: Int = 0

    var llmRequested: Bool = false
    var llmAvailable: Bool = false
    var llmUsed:      Bool = false
    var llmMillis:    Int = 0
    var llmError:     String?

    var fallbackUsed: Bool = false
    var iOSVersion:   String = ""
    var itemCount:    Int = 0

    // Neu: Diagnose der verbesserten Pipeline
    var saliencyCropUsed: Bool = false
    var highConfidenceLabels: [String] = []
    var lowConfidenceLabels:  [String] = []
}

enum FoodPhotoAnalyzerError: Error {
    case unavailable, invalidImage, modelFailed
}

/// Live-Fortschritts-Stages für die Photo-Analyse. Wird über einen
/// Callback an die UI gemeldet, damit der User sieht was passiert.
enum AnalysisStage {
    case visionStarting
    case visionCompleted(topLabels: [String])
    case llmReasoning
    case llmReasoningResult(text: String)
    case llmVerifying
    case llmVerifyingResult(text: String)
    case llmExtracting
    case finished

    var displayMessage: String {
        switch self {
        case .visionStarting:        return "Bild wird analysiert…"
        case .visionCompleted(let l): return "Erkannt: " + l.prefix(4).joined(separator: ", ")
        case .llmReasoning:          return "KI überlegt was es ist…"
        case .llmReasoningResult:    return "Komponenten identifiziert"
        case .llmVerifying:          return "Selbstprüfung läuft…"
        case .llmVerifyingResult:    return "Plausibilität geprüft"
        case .llmExtracting:         return "Nährwerte werden geschätzt…"
        case .finished:              return "Fertig"
        }
    }

    var systemImage: String {
        switch self {
        case .visionStarting, .visionCompleted: return "viewfinder"
        case .llmReasoning, .llmReasoningResult: return "brain"
        case .llmVerifying, .llmVerifyingResult: return "checkmark.circle"
        case .llmExtracting:                     return "scalemass"
        case .finished:                          return "checkmark.seal.fill"
        }
    }
}

typealias AnalysisProgressHandler = @Sendable (AnalysisStage) async -> Void

// MARK: - Labeled observation mit Konfidenz

private struct ScoredLabel: Comparable {
    let label: String
    let confidence: Float
    static func < (l: ScoredLabel, r: ScoredLabel) -> Bool { l.confidence < r.confidence }
}

// MARK: - FoodPhotoAnalyzer

enum FoodPhotoAnalyzer {

    static var isLLMAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    static func analyze(image: UIImage) async throws -> [RecognizedFoodItem] {
        let (items, _) = try await analyzeDetailed(image: image)
        return items
    }

    static func analyzeDetailed(image: UIImage,
                                labelHints: [String]? = nil,
                                kindHint: FoodKind? = nil,
                                progress: AnalysisProgressHandler? = nil) async throws -> ([RecognizedFoodItem], AnalysisDiagnostics) {
        var diag = AnalysisDiagnostics()
        diag.iOSVersion = await MainActor.run { UIDevice.current.systemVersion }

        // ── Stage 1: Vision mit Saliency-Crop ────────────────────────────────
        await progress?(.visionStarting)
        let scoredLabels: [ScoredLabel]
        let t0 = Date()

        if let labelHints, !labelHints.isEmpty {
            scoredLabels = labelHints.enumerated().map { i, l in
                ScoredLabel(label: l, confidence: Float(1.0 - Double(i) * 0.05))
            }
        } else {
            do {
                scoredLabels = try await visionScoredLabels(for: image, diag: &diag)
                diag.visionMillis = Int(Date().timeIntervalSince(t0) * 1000)
            } catch {
                diag.llmError = "Vision: \(error.localizedDescription)"
                diag.visionMillis = Int(Date().timeIntervalSince(t0) * 1000)
                scoredLabels = []
            }
        }

        let highConf = scoredLabels.filter { $0.confidence >= 0.35 }.map(\.label)
        let lowConf  = scoredLabels.filter { $0.confidence < 0.35 }.map(\.label)
        diag.visionLabels     = scoredLabels.map(\.label)
        diag.highConfidenceLabels = highConf
        diag.lowConfidenceLabels  = lowConf

        await progress?(.visionCompleted(topLabels: scoredLabels.prefix(5).map(\.label)))

        // ── Stage 2: LLM mit Konfidenz-Kontext ───────────────────────────────
        diag.llmAvailable = isLLMAvailable
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), diag.llmAvailable, !scoredLabels.isEmpty {
            diag.llmRequested = true
            let t1 = Date()
            do {
                let llm = try await analyzeWithLLM(scoredLabels: scoredLabels, kindHint: kindHint, progress: progress)
                diag.llmMillis = Int(Date().timeIntervalSince(t1) * 1000)
                if !llm.isEmpty {
                    diag.llmUsed  = true
                    diag.itemCount = llm.count
                    await progress?(.finished)
                    return (llm, diag)
                }
            } catch {
                diag.llmError = String(describing: error)
                diag.llmMillis = Int(Date().timeIntervalSince(t1) * 1000)
            }
        }
        #endif

        // ── Stage 3: Heuristic Fallback ───────────────────────────────────────
        diag.fallbackUsed = true
        let items = heuristicItems(from: highConf.isEmpty ? scoredLabels.map(\.label) : highConf)
        diag.itemCount = items.count
        await progress?(.finished)
        return (items, diag)
    }

    // MARK: - Vision: Saliency-Crop + Doppelanalyse

    /// Führt VNClassifyImageRequest auf dem Originalbild UND auf einem
    /// Saliency-Crop aus. Labels die in beiden Analysen auftauchen erhalten
    /// einen Konfidenz-Boost — das reduziert Hintergrund-Rauschen stark.
    private static func visionScoredLabels(for image: UIImage,
                                           diag: inout AnalysisDiagnostics) async throws -> [ScoredLabel] {
        guard let cgImage = image.cgImage else { throw FoodPhotoAnalyzerError.invalidImage }

        // 1a. Vollbild klassifizieren
        let fullLabels = try await classify(cgImage: cgImage, confidenceThreshold: 0.1, maxResults: 20)

        // 1b. Saliency-Region bestimmen und croppen
        var croppedLabels: [ScoredLabel] = []
        if let salientCGImage = await saliencyCrop(of: cgImage) {
            diag.saliencyCropUsed = true
            croppedLabels = (try? await classify(cgImage: salientCGImage, confidenceThreshold: 0.1, maxResults: 20)) ?? []
        }

        // 1c. Labels aus beiden Analysen zusammenführen
        //     Labels die in beiden auftauchen: max(conf) * 1.4 (Boost wegen Übereinstimmung)
        //     Labels nur im Crop:      conf * 1.1 (leichter Boost, da Fokus-Region)
        //     Labels nur im Vollbild:  conf * 0.7 (Abzug, kann Hintergrund sein)
        var combined: [String: Float] = [:]

        for sl in croppedLabels {
            let key = sl.label.lowercased()
            combined[key] = max(combined[key] ?? 0, sl.confidence * 1.1)
        }
        for sl in fullLabels {
            let key = sl.label.lowercased()
            if let existing = combined[key] {
                // In beiden Analysen → Boost
                combined[key] = max(existing, sl.confidence) * 1.4
            } else {
                // Nur im Vollbild → Abzug (wahrscheinlich Hintergrund)
                combined[key] = sl.confidence * 0.7
            }
        }

        // Nicht-Lebensmittel-Labels entfernen
        let foodFiltered = combined
            .filter { isFoodRelated(label: $0.key) }
            .map { ScoredLabel(label: $0.key.replacingOccurrences(of: "_", with: " "), confidence: $0.value) }
            .sorted { $0.confidence > $1.confidence }
            .prefix(15)

        return Array(foodFiltered)
    }

    /// Klassifiziert ein CGImage und gibt Scored Labels zurück.
    private static func classify(cgImage: CGImage,
                                  confidenceThreshold: Float,
                                  maxResults: Int) async throws -> [ScoredLabel] {
        final class Resumer { var done = false }
        let state = Resumer()
        return try await withCheckedThrowingContinuation { cont in
            let request = VNClassifyImageRequest { req, err in
                guard !state.done else { return }
                state.done = true
                if let err { cont.resume(throwing: err); return }
                let obs = (req.results as? [VNClassificationObservation]) ?? []
                let labels = obs
                    .filter { $0.confidence > confidenceThreshold }
                    .prefix(maxResults)
                    .map { ScoredLabel(
                        label: $0.identifier.replacingOccurrences(of: "_", with: " "),
                        confidence: $0.confidence
                    )}
                cont.resume(returning: labels)
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

    /// Findet die Saliency-Region (Aufmerksamkeitsbereich) im Bild und gibt
    /// ein auf diesen Bereich zugeschnittenes CGImage zurück.
    private static func saliencyCrop(of cgImage: CGImage) async -> CGImage? {
        final class Resumer { var done = false }
        let state = Resumer()
        return await withCheckedContinuation { cont in
            let request = VNGenerateAttentionBasedSaliencyImageRequest { req, err in
                guard !state.done else { return }
                state.done = true
                guard err == nil,
                      let result = req.results?.first as? VNSaliencyImageObservation,
                      let salientObjects = result.salientObjects, !salientObjects.isEmpty
                else { cont.resume(returning: nil); return }

                // Bounding-Box aller salient objects vereinen
                let union = salientObjects.reduce(CGRect.null) { $0.union($1.boundingBox) }

                // VN-Koordinaten (0…1, Origin bottom-left) → CGImage-Pixel
                let w = CGFloat(cgImage.width)
                let h = CGFloat(cgImage.height)
                // Etwas Padding (10%) damit kein Rand abgeschnitten wird
                let padding: CGFloat = 0.10
                let cropRect = CGRect(
                    x: max(0, (union.minX - padding) * w),
                    y: max(0, (1 - union.maxY - padding) * h),      // y-Achse flippen
                    width: min(w, (union.width + 2 * padding) * w),
                    height: min(h, (union.height + 2 * padding) * h)
                )
                let cropped = cgImage.cropping(to: cropRect)
                cont.resume(returning: cropped)
            }
            do {
                try VNImageRequestHandler(cgImage: cgImage).perform([request])
            } catch {
                guard !state.done else { return }
                state.done = true
                cont.resume(returning: nil)
            }
        }
    }

    // MARK: - Label-Filter: offensichtliche Nicht-Lebensmittel raus

    private static let nonFoodKeywords: Set<String> = [
        "person", "people", "man", "woman", "child", "hand", "finger",
        "table", "chair", "furniture", "wood", "floor", "wall", "ceiling",
        "cloth", "textile", "paper", "napkin", "serviette",
        "building", "architecture", "sky", "outdoor", "indoor",
        "animal", "cat", "dog", "bird",
        "vehicle", "car", "bicycle",
        "text", "sign", "label",
        "phone", "computer", "device",
        "plant", "tree", "flower", "grass",    // Ausnahme: falls sie food-relevant sind
    ]

    private static func isFoodRelated(label: String) -> Bool {
        let lower = label.lowercased()
        // Wenn ein Non-Food-Keyword enthalten ist UND kein Food-Keyword
        let hasNonFood = nonFoodKeywords.contains { lower.contains($0) }
        let hasFoodHint = ["food", "dish", "meal", "eat", "drink", "fruit", "vegetable",
                           "meat", "bread", "pasta", "rice", "soup", "salad", "cake",
                           "pizza", "burger", "snack", "beverage", "juice", "wine",
                           "beer", "coffee", "tea", "milk", "egg", "fish", "cheese",
                           "potato", "tomato", "carrot", "onion", "pepper", "mushroom",
                           "apple", "banana", "orange", "strawberry", "berry", "nut",
                           "chicken", "beef", "pork", "lamb", "seafood", "shrimp",
                           "sausage", "ham", "salami", "steak", "schnitzel",
                           "noodle", "dough", "sauce", "cream", "butter", "oil",
                           "chocolate", "sweet", "dessert", "ice cream", "cookie",
                           "pretzel", "sandwich", "wrap", "curry", "stew"].contains { lower.contains($0) }
        return hasFoodHint || !hasNonFood
    }

    // MARK: - Foundation Models

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func analyzeWithLLM(scoredLabels: [ScoredLabel],
                                        kindHint: FoodKind?,
                                        progress: AnalysisProgressHandler?) async throws -> [RecognizedFoodItem] {
        // Nur der realistische Pass meldet Progress (sonst doppelt). Der
        // generous Pass läuft parallel still mit.
        async let passA = llmPass(scoredLabels: scoredLabels, style: .realistic, kindHint: kindHint, progress: progress)
        async let passB = llmPass(scoredLabels: scoredLabels, style: .generous,  kindHint: kindHint, progress: nil)
        let (a, b) = try await (passA, passB)
        return mergeBlended(realistic: a, generous: b)
    }

    private enum LLMStyle { case realistic, generous }

    @available(iOS 26.0, *)
    private static func llmPass(scoredLabels: [ScoredLabel],
                                 style: LLMStyle,
                                 kindHint: FoodKind?,
                                 progress: AnalysisProgressHandler?) async throws -> [RecognizedFoodItem] {
        let toneLine: String
        switch style {
        case .realistic:
            toneLine = "Schätze realistische Durchschnittswerte — am oberen Rand des üblichen Bereichs, aber nicht übertrieben."
        case .generous:
            toneLine = "Gehe von einer typischen Restaurant- bzw. sättigenden Portion aus. Fette, Öle, Saucen grosszügig einrechnen."
        }

        let kindContext: String
        switch kindHint {
        case .drink:
            kindContext = "HINT: Der Nutzer hat bestätigt, dass das Foto ein GETRÄNK zeigt. Identifiziere ausschliesslich das Getränk."
        case .food:
            kindContext = "HINT: Der Nutzer hat bestätigt, dass das Foto eine SPEISE zeigt. Fokus auf Essen, keine Getränke."
        case nil:
            kindContext = ""
        }

        // Konfidenz-Gruppen formatieren
        let highConf = scoredLabels.filter { $0.confidence >= 0.35 }
        let midConf  = scoredLabels.filter { $0.confidence >= 0.20 && $0.confidence < 0.35 }
        let lowConf  = scoredLabels.filter { $0.confidence < 0.20 }

        func fmt(_ sl: ScoredLabel) -> String {
            String(format: "%@ (%.0f%%)", sl.label, sl.confidence * 100)
        }

        var labelBlock = ""
        if !highConf.isEmpty {
            labelBlock += "SICHER (>35%): \(highConf.map(fmt).joined(separator: ", "))\n"
        }
        if !midConf.isEmpty {
            labelBlock += "MÖGLICH (20–35%): \(midConf.map(fmt).joined(separator: ", "))\n"
        }
        if !lowConf.isEmpty {
            labelBlock += "UNSICHER (<20%, oft falsch): \(lowConf.map(fmt).joined(separator: ", "))\n"
        }

        let instructions = """
        Du bist ein Ernährungsassistent. Du bekommst Labels einer Bild-KI und
        sollst daraus identifizieren, was auf dem Foto zu sehen ist.

        ALLERWICHTIGSTE REGEL — VERTRAUE DEN VISION-LABELS:
        Die Vision-Labels sind das, was wirklich im Bild zu sehen ist. Du darfst
        sie NICHT umdeuten, durch andere Lebensmittel ersetzen oder eigene
        Komponenten erfinden. Wenn die Labels "ice cream" und "dessert"
        enthalten, IST es ein Eis/Dessert — nicht Brotzeit, nicht Schinken,
        nicht Nudeln.

        SCHRITT 1 — KATEGORIE:
        Bestimme zuerst die Hauptkategorie aus den Labels:
        - "ice cream", "frozen dessert", "dessert", "cake", "cookie", "chocolate"
          → DESSERT (ein einzelner Eintrag, NICHT in Bestandteile zerlegen)
        - "pizza" → PIZZA (ein Eintrag)
        - "burger", "sandwich", "wrap" → BURGER/SANDWICH (ein Eintrag)
        - "salad" → SALAT (ein Eintrag)
        - "soup", "stew" → SUPPE/EINTOPF (ein Eintrag)
        - "pasta", "noodle" → NUDELGERICHT (ein Eintrag)
        - "rice" mit anderen Zutaten → REISGERICHT (ein Eintrag)
        - Mehrere klare Hauptzutaten ohne Sammelbegriff → EINZELZUTATEN

        SCHRITT 2 — NUR LABELS NUTZEN, DIE WIRKLICH DA SIND:
        Erfinde NIEMALS Zutaten, die nicht in den Labels stehen.
        Beispiel: Labels = "ice cream, dessert, bowl, spoon, kiwi"
        → Antwort: "Eis mit Kiwi" — NICHT "Brot, Prosciutto, Gewürze".

        \(kindContext)

        \(toneLine)
        """

        let session = LanguageModelSession(instructions: instructions)

        // ── Turn 1: Kategorie + Identifikation ─────────────────────────────
        // Wir zwingen das Modell, zuerst die Kategorie zu bestimmen — nicht
        // sofort zu zerlegen. Das vermeidet die "Brotzeit-Halluzination".
        await progress?(.llmReasoning)
        let reasoningResponse = try await session.respond(to: """
            Vision-Labels:
            \(labelBlock)

            Antworte in 2-3 Sätzen:
            1. Welche Hauptkategorie zeigen die Labels? (Dessert, Pizza, Salat,
               Suppe, Hauptgericht, Brotzeit, Snack, Getränk, ...)
            2. Was siehst du genau? Nenne nur Lebensmittel, die in den Labels
               wirklich vorkommen — keine Erfindungen.
            3. Ist es EIN Gericht (z.B. Eis) oder mehrere getrennte Komponenten?
            """)
        let reasoningText = String(describing: reasoningResponse.content)
        await progress?(.llmReasoningResult(text: reasoningText))

        // ── Turn 2: Plausibilitäts-Check gegen die Labels ─────────────────
        await progress?(.llmVerifying)
        let verifyResponse = try await session.respond(to: """
            Kontrolliere deine Antwort:
            - Steht jede Zutat, die du nennst, wirklich in den Vision-Labels?
            - Hast du eine Zutat erfunden, die NICHT in den Labels steht? Falls ja,
              ENTFERNE sie.
            - Bei Sammelbegriffen (Eis, Pizza, Burger, Suppe): hast du das
              Gericht als EINEN Eintrag belassen statt unnötig zu zerlegen?

            Antworte kurz (1-2 Sätze) und korrigiere falls nötig.
            """)
        let verifyText = String(describing: verifyResponse.content)
        await progress?(.llmVerifyingResult(text: verifyText))

        // ── Turn 3: Strukturierte Extraktion ─────────────────────────────
        await progress?(.llmExtracting)
        let response = try await session.respond(
            to: """
            Liste die Komponenten der Mahlzeit als strukturiertes Ergebnis.
            Nur Lebensmittel/Getränke aus deiner Antwort — keine neuen Zutaten.
            Deutscher Name, Portion in Gramm (Getränke in ml), Kalorien, KH.
            """,
            generating: LLMFoodResponse.self
        )

        return response.content.items.map {
            RecognizedFoodItem(
                name: $0.name,
                portionGrams: max(1, $0.portionGrams),
                calories: max(0, $0.calories),
                carbsGrams: max(0, $0.carbsGrams)
            )
        }
    }

    private static let generousBlend: Double = 0.5

    private static func mergeBlended(realistic a: [RecognizedFoodItem],
                                     generous  b: [RecognizedFoodItem]) -> [RecognizedFoodItem] {
        if a.isEmpty { return b }
        if b.isEmpty { return a }

        func blend(_ r: Int, _ g: Int) -> Int {
            r + Int((Double(max(0, g - r)) * generousBlend).rounded())
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
        @Guide(description: "Liste aller erkannten Lebensmittel oder Getränke. Nur plausible Kombinationen.")
        let items: [LLMFoodItem]
    }

    @available(iOS 26.0, *)
    @Generable
    fileprivate struct LLMFoodItem {
        @Guide(description: "Name auf Deutsch, z. B. 'Tomaten-Kartoffel-Eintopf' oder 'Apfelschorle'.")
        let name: String
        @Guide(description: "Geschätzte Portionsgrösse in Gramm.")
        let portionGrams: Int
        @Guide(description: "Geschätzte Kalorien der Portion.")
        let calories: Int
        @Guide(description: "Geschätzte Kohlenhydrate der Portion in Gramm.")
        let carbsGrams: Int
    }
    #endif

    // MARK: - Heuristic Fallback

    private static func heuristicItems(from labels: [String]) -> [RecognizedFoodItem] {
        labels.prefix(3).map { label in
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
        let l = label.lowercased()
        if l.contains("pizza")      { return (250, 720, 80) }
        if l.contains("burger")     { return (260, 760, 55) }
        if l.contains("salad")      { return (250, 220, 15) }
        if l.contains("pasta") || l.contains("noodle") { return (300, 520, 80) }
        if l.contains("bread")      { return (60, 170, 30) }
        if l.contains("potato")     { return (200, 160, 36) }
        if l.contains("tomato")     { return (150, 30, 6) }
        if l.contains("carrot")     { return (100, 40, 9) }
        if l.contains("apple")      { return (180, 100, 26) }
        if l.contains("banana")     { return (120, 110, 28) }
        if l.contains("coffee")     { return (200, 15, 2) }
        if l.contains("beer")       { return (500, 250, 22) }
        if l.contains("wine")       { return (150, 135, 5) }
        if l.contains("water")      { return (300, 0, 0) }
        if l.contains("rice")       { return (250, 340, 70) }
        if l.contains("fries")      { return (180, 560, 65) }
        if l.contains("meat") || l.contains("chicken") || l.contains("beef") { return (200, 320, 0) }
        return (200, 320, 35)
    }
}
