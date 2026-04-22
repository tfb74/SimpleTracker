import Foundation

enum BiologicalSex {
    case male, female, unspecified
}

struct ProfileSnapshot {
    var ageYears: Int
    var weightKg: Double
    var heightCm: Double
    var sex: BiologicalSex

    static let neutral = ProfileSnapshot(ageYears: 35, weightKg: 75, heightCm: 175, sex: .unspecified)

    var bmi: Double {
        guard heightCm > 0 else { return 0 }
        let heightMeters = heightCm / 100
        return weightKg / (heightMeters * heightMeters)
    }
}

struct DailyNutritionBaseline {
    let restingCalories: Double
    let totalCalories: Double
    let carbReferenceLowGrams: Double
    let carbReferenceHighGrams: Double
}

enum NutritionBaselineEstimator {
    /// Mifflin-St Jeor as a pragmatic day-level estimate for resting needs.
    static func restingCaloriesPerDay(profile: ProfileSnapshot) -> Double {
        let age = Double(profile.ageYears > 0 ? profile.ageYears : ProfileSnapshot.neutral.ageYears)
        let weight = profile.weightKg > 0 ? profile.weightKg : ProfileSnapshot.neutral.weightKg
        let height = profile.heightCm > 0 ? profile.heightCm : ProfileSnapshot.neutral.heightCm

        let sexOffset: Double
        switch profile.sex {
        case .male:        sexOffset = 5
        case .female:      sexOffset = -161
        case .unspecified: sexOffset = -78
        }

        return max(0, 10 * weight + 6.25 * height - 5 * age + sexOffset)
    }

    static func estimate(for date: Date,
                         activeCalories: Double,
                         profile: ProfileSnapshot,
                         now: Date = Date()) -> DailyNutritionBaseline {
        let restingFullDay = restingCaloriesPerDay(profile: profile)
        let completion = dayCompletion(for: date, now: now)
        let restingCalories = restingFullDay * completion
        let totalCalories = restingCalories + max(0, activeCalories)

        // Show a corridor instead of a fake-precise carb target.
        let carbLow = max(130, totalCalories * 0.45 / 4)
        let carbHigh = max(carbLow, totalCalories * 0.55 / 4)

        return DailyNutritionBaseline(
            restingCalories: restingCalories,
            totalCalories: totalCalories,
            carbReferenceLowGrams: carbLow,
            carbReferenceHighGrams: carbHigh
        )
    }

    private static func dayCompletion(for date: Date, now: Date) -> Double {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return 1 }
        if now <= start { return 0 }
        if now >= end { return 1 }
        return now.timeIntervalSince(start) / end.timeIntervalSince(start)
    }
}

enum CaloricEstimator {
    /// MET lookup (Compendium of Physical Activities, piecewise-linear).
    static func metValue(type: WorkoutType, speedMPS: Double) -> Double {
        let kmh = max(0, speedMPS) * 3.6
        switch type {
        case .walking:
            return max(2.0, min(7.5, 1.5 + kmh * 0.85))
        case .running:
            return max(6.0, min(16.0, 1.5 + kmh * 0.9))
        case .cycling:
            return max(3.5, min(15.8, -1.0 + kmh * 0.5))
        case .hiking:
            return max(5.0, min(9.0, 3.5 + kmh * 0.75))
        // Non-GPS / speed-less activities: fixed typical MET values.
        case .swimming:   return 7.0
        case .rowing:     return 7.0
        case .elliptical: return 5.0
        case .stairs:     return 8.0
        case .yoga:       return 2.5
        case .strength:   return 5.0
        case .hiit:       return 8.5
        case .dance:      return 5.5
        case .tennis:     return 7.3
        case .soccer:     return 8.0
        case .basketball: return 6.5
        case .golf:       return 4.3
        case .skating:    return 7.0
        case .skiing:     return 6.0
        case .other:      return 4.0
        }
    }

    /// Active calories (excluding resting metabolism), adjusted for weight/sex/age.
    static func estimate(type: WorkoutType,
                         distanceMeters: Double,
                         durationSec: TimeInterval,
                         profile: ProfileSnapshot) -> Double {
        guard durationSec > 0 else { return 0 }
        let speed  = distanceMeters / durationSec
        let met    = metValue(type: type, speedMPS: speed)
        let weight = profile.weightKg > 0 ? profile.weightKg : ProfileSnapshot.neutral.weightKg
        let hours  = durationSec / 3600

        var kcal = (met - 1.0) * weight * hours

        switch profile.sex {
        case .male:        kcal *= 1.00
        case .female:      kcal *= 0.90
        case .unspecified: kcal *= 0.95
        }

        if profile.ageYears > 30 {
            let decades = Double(profile.ageYears - 30) / 10
            kcal *= max(0.85, 1.0 - decades * 0.01)
        }

        return max(0, kcal)
    }
}
