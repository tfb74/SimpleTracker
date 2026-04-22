import Foundation
import SwiftUI

/// A one-tap food/drink entry — fills name, kind, calories and carbs so the
/// user doesn't have to think about grams, BE or manual conversion.
///
/// Icons are SF Symbols (matching the rest of the app), not emojis — the
/// user explicitly asked for a consistent, non-cartoon look.
struct QuickFoodPreset: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var systemImage: String      // SF Symbol name, e.g. "cup.and.saucer.fill"
    var tintName: String         // "blue" | "orange" | …  — resolved via `tint`
    var kind: FoodKind
    /// Typical portion description shown in the chip (e.g. "250 ml", "60 g").
    var portionLabel: String
    var calories: Double
    var carbsGrams: Double
    /// True for the bundled defaults — these can't be deleted.
    var isBuiltIn: Bool

    init(id: UUID = UUID(),
         name: String,
         systemImage: String,
         tintName: String,
         kind: FoodKind,
         portionLabel: String,
         calories: Double,
         carbsGrams: Double,
         isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.systemImage = systemImage
        self.tintName = tintName
        self.kind = kind
        self.portionLabel = portionLabel
        self.calories = calories
        self.carbsGrams = carbsGrams
        self.isBuiltIn = isBuiltIn
    }

    var tint: Color { Self.color(named: tintName) }

    static func color(named: String) -> Color {
        switch named {
        case "blue":   return .blue
        case "red":    return .red
        case "green":  return .green
        case "orange": return .orange
        case "yellow": return .yellow
        case "purple": return .purple
        case "pink":   return .pink
        case "mint":   return .mint
        case "teal":   return .teal
        case "cyan":   return .cyan
        case "brown":  return .brown
        case "indigo": return .indigo
        case "gray":   return .gray
        default:       return .accentColor
        }
    }

    /// Available tint names for the custom-preset color picker.
    static let availableTints: [String] = [
        "blue", "cyan", "teal", "mint", "green",
        "yellow", "orange", "red", "pink", "purple",
        "indigo", "brown", "gray"
    ]
}

extension QuickFoodPreset {
    /// Sensible realistic defaults — values based on typical DACH-region portions.
    /// SF-Symbol + tint chosen to match the statistics screen aesthetic.
    static let builtInDrinks: [QuickFoodPreset] = [
        .init(name: "Wasser",         systemImage: "drop.fill",                              tintName: "cyan",   kind: .drink, portionLabel: "250 ml", calories: 0,   carbsGrams: 0,   isBuiltIn: true),
        .init(name: "Kaffee schwarz", systemImage: "cup.and.saucer.fill",                    tintName: "brown",  kind: .drink, portionLabel: "250 ml", calories: 5,   carbsGrams: 1,   isBuiltIn: true),
        .init(name: "Cappuccino",     systemImage: "cup.and.saucer.fill",                    tintName: "orange", kind: .drink, portionLabel: "250 ml", calories: 90,  carbsGrams: 8,   isBuiltIn: true),
        .init(name: "Tee mit Milch",  systemImage: "cup.and.saucer.fill",                    tintName: "green",  kind: .drink, portionLabel: "250 ml", calories: 30,  carbsGrams: 3,   isBuiltIn: true),
        .init(name: "Apfelschorle",   systemImage: "takeoutbag.and.cup.and.straw.fill",      tintName: "green",  kind: .drink, portionLabel: "250 ml", calories: 55,  carbsGrams: 13,  isBuiltIn: true),
        .init(name: "Cola",           systemImage: "waterbottle.fill",                       tintName: "red",    kind: .drink, portionLabel: "250 ml", calories: 105, carbsGrams: 27,  isBuiltIn: true),
        .init(name: "Fanta",          systemImage: "waterbottle.fill",                       tintName: "orange", kind: .drink, portionLabel: "250 ml", calories: 115, carbsGrams: 28,  isBuiltIn: true),
        .init(name: "Sprite",         systemImage: "waterbottle.fill",                       tintName: "mint",   kind: .drink, portionLabel: "250 ml", calories: 110, carbsGrams: 26,  isBuiltIn: true),
        .init(name: "Orangensaft",    systemImage: "waterbottle.fill",                       tintName: "yellow", kind: .drink, portionLabel: "250 ml", calories: 115, carbsGrams: 27,  isBuiltIn: true),
        .init(name: "Bier",           systemImage: "mug.fill",                               tintName: "yellow", kind: .drink, portionLabel: "500 ml", calories: 215, carbsGrams: 18,  isBuiltIn: true),
    ]

    static let builtInSnacks: [QuickFoodPreset] = [
        .init(name: "Apfel",          systemImage: "leaf.fill",                              tintName: "red",    kind: .food,  portionLabel: "180 g",  calories: 95,  carbsGrams: 25,  isBuiltIn: true),
        .init(name: "Banane",         systemImage: "leaf.fill",                              tintName: "yellow", kind: .food,  portionLabel: "120 g",  calories: 105, carbsGrams: 27,  isBuiltIn: true),
        .init(name: "Müsliriegel",    systemImage: "square.stack.fill",                      tintName: "brown",  kind: .food,  portionLabel: "30 g",   calories: 130, carbsGrams: 20,  isBuiltIn: true),
        .init(name: "Proteinriegel",  systemImage: "dumbbell.fill",                          tintName: "purple", kind: .food,  portionLabel: "45 g",   calories: 190, carbsGrams: 20,  isBuiltIn: true),
        .init(name: "Schokoriegel",   systemImage: "square.fill",                            tintName: "brown",  kind: .food,  portionLabel: "50 g",   calories: 250, carbsGrams: 30,  isBuiltIn: true),
        .init(name: "Croissant",      systemImage: "moon.fill",                              tintName: "orange", kind: .food,  portionLabel: "60 g",   calories: 240, carbsGrams: 26,  isBuiltIn: true),
        .init(name: "Donut",          systemImage: "circle.circle.fill",                     tintName: "pink",   kind: .food,  portionLabel: "70 g",   calories: 260, carbsGrams: 32,  isBuiltIn: true),
        .init(name: "Sandwich",       systemImage: "rectangle.stack.fill",                   tintName: "green",  kind: .food,  portionLabel: "200 g",  calories: 350, carbsGrams: 40,  isBuiltIn: true),
        .init(name: "Pizzastück",     systemImage: "triangle.fill",                          tintName: "red",    kind: .food,  portionLabel: "100 g",  calories: 270, carbsGrams: 33,  isBuiltIn: true),
        .init(name: "Burger",         systemImage: "circle.grid.2x2.fill",                   tintName: "brown",  kind: .food,  portionLabel: "250 g",  calories: 500, carbsGrams: 40,  isBuiltIn: true),
    ]

    static let allBuiltIn: [QuickFoodPreset] = builtInDrinks + builtInSnacks

    /// SF Symbols offered in the "add custom preset" picker — chosen so
    /// they render well at small sizes and fit the food/drink domain.
    static let customSymbolChoicesFood: [String] = [
        "fork.knife", "leaf.fill", "carrot.fill", "fish.fill", "birthday.cake.fill",
        "popcorn.fill", "frying.pan.fill", "takeoutbag.and.cup.and.straw.fill",
        "square.stack.fill", "rectangle.stack.fill", "triangle.fill", "circle.grid.2x2.fill",
        "moon.fill", "dumbbell.fill", "square.fill", "circle.circle.fill"
    ]
    static let customSymbolChoicesDrink: [String] = [
        "cup.and.saucer.fill", "mug.fill", "waterbottle.fill", "drop.fill",
        "takeoutbag.and.cup.and.straw.fill", "wineglass.fill", "cocktail.fill"
    ]
}
