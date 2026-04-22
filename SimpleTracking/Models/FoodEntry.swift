import Foundation

enum FoodSource: String, Codable {
    case manual, barcode, photo
}

struct FoodNutritionSnapshot: Hashable {
    let calories: Double
    let carbsGrams: Double
    let caloriesAreEstimated: Bool

    var breadUnits: Double {
        FoodEntry.breadUnits(fromCarbs: carbsGrams)
    }
}

enum FoodKind: String, Codable, CaseIterable {
    case food, drink

    var displayName: String {
        switch self {
        case .food:  return lt("Essen")
        case .drink: return lt("Getränk")
        }
    }

    var systemImage: String {
        switch self {
        case .food:  return "fork.knife"
        case .drink: return "cup.and.saucer.fill"
        }
    }
}

struct FoodEntry: Identifiable, Codable, Hashable {
    static let gramsPerBreadUnit = 12.0
    static let caloriesPerGramCarb = 4.0

    let id: UUID
    var timestamp: Date
    var name: String
    var kind: FoodKind
    var portionGrams: Double?      // optional, for solids
    var portionMilliliters: Double? // optional, for drinks
    var calories: Double           // kcal total for this portion
    var carbsGrams: Double         // total carbs for this portion (for BE)
    var source: FoodSource
    var barcode: String?
    /// UUIDs der zugehörigen HealthKit-Samples (dietaryEnergy / Carbs / Water),
    /// damit wir sie beim Löschen des Eintrags auch aus Apple Health entfernen.
    /// Optional + Default nil, damit alte persistierte Einträge weiterhin dekodieren.
    var healthKitSampleIDs: [String]? = nil

    /// Broteinheiten — 1 BE = 12 g Kohlenhydrate
    var breadUnits: Double { resolvedNutrition.breadUnits }
    var resolvedCalories: Double { resolvedNutrition.calories }
    var resolvedCarbsGrams: Double { resolvedNutrition.carbsGrams }
    var hasEstimatedCalories: Bool { resolvedNutrition.caloriesAreEstimated }

    var resolvedNutrition: FoodNutritionSnapshot {
        let sanitizedCalories = max(0, calories)
        let sanitizedCarbs = max(0, carbsGrams)
        let caloriesAreEstimated = sanitizedCalories == 0 && sanitizedCarbs > 0
        let resolvedCalories = sanitizedCalories > 0
            ? sanitizedCalories
            : Self.estimatedCalories(fromCarbs: sanitizedCarbs)

        return FoodNutritionSnapshot(
            calories: resolvedCalories,
            carbsGrams: sanitizedCarbs,
            caloriesAreEstimated: caloriesAreEstimated
        )
    }

    init(id: UUID = UUID(),
         timestamp: Date = Date(),
         name: String,
         kind: FoodKind = .food,
         portionGrams: Double? = nil,
         portionMilliliters: Double? = nil,
         calories: Double,
         carbsGrams: Double,
         source: FoodSource,
         barcode: String? = nil,
         healthKitSampleIDs: [String]? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.name = name
        self.kind = kind
        self.portionGrams = portionGrams
        self.portionMilliliters = portionMilliliters
        self.calories = calories
        self.carbsGrams = carbsGrams
        self.source = source
        self.barcode = barcode
        self.healthKitSampleIDs = healthKitSampleIDs
    }

    static func carbs(fromBreadUnits breadUnits: Double) -> Double {
        max(0, breadUnits) * gramsPerBreadUnit
    }

    static func breadUnits(fromCarbs carbsGrams: Double) -> Double {
        max(0, carbsGrams) / gramsPerBreadUnit
    }

    static func estimatedCalories(fromCarbs carbsGrams: Double) -> Double {
        max(0, carbsGrams) * caloriesPerGramCarb
    }
}
