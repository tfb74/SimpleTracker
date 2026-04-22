import Foundation

/// Personalisierter Fitness-Score pro Workout.
///
/// Formel:
///   base    = calories × 1.5 + distanceKm × distanceFactor(BMI) + durationMin × 0.4
///   score   = base × ageFactor × intensityBonus
///
/// Designprinzip: Ein Kilometer zählt für einen adipösen Menschen deutlich mehr,
/// weil er pro kg mehr Masse bewegt. Das Alter erhöht den Faktor, weil Regeneration
/// und Herz-Kreislauf-Belastung mit dem Alter steigen.
struct WorkoutScore {

    let rawScore: Double       // ungerundeter Wert für Leaderboard (×10 = Int)
    let displayScore: Int      // gerundeter Anzeigewert
    let grade: Grade           // S / A / B / C / D
    let breakdown: Breakdown   // Einzelfaktoren für Detail-Ansicht

    // MARK: - Grade

    enum Grade: String {
        case s = "S", a = "A", b = "B", c = "C", d = "D"

        var color: String {   // system-color name
            switch self {
            case .s: return "yellow"
            case .a: return "green"
            case .b: return "blue"
            case .c: return "orange"
            case .d: return "red"
            }
        }

        var label: String { "Bewertung \(rawValue)" }
    }

    // MARK: - Breakdown

    struct Breakdown {
        let caloriePoints: Double
        let distancePoints: Double
        let durationPoints: Double
        let ageFactor: Double
        let bmiLabel: String
        let distanceFactor: Double
        let intensityBonus: Double
    }

    // MARK: - Factory

    static func calculate(
        calories: Double,
        distanceMeters: Double,
        durationSeconds: TimeInterval,
        averageSpeedMPS: Double,
        workoutType: WorkoutType,
        settings: UserSettings
    ) -> WorkoutScore {

        let distanceKm  = distanceMeters / 1_000
        let durationMin = durationSeconds / 60

        // ── Distance factor based on BMI ─────────────────────────────────────
        // Normal weight: 10 pts/km  |  Overweight: 14  |  Obese: 20
        // Rationale: heavier body lifts more mass with every step → more effort
        let distanceFactor: Double
        if settings.profileComplete {
            switch settings.bmiCategory {
            case .underweight: distanceFactor = 8
            case .normal:      distanceFactor = 10
            case .overweight:  distanceFactor = 14
            case .obese:       distanceFactor = 20
            }
        } else {
            distanceFactor = 10
        }

        // ── Age factor ───────────────────────────────────────────────────────
        // Under 20: 0.90  |  20–30: 1.00  |  30–40: 1.06
        // 40–50: 1.14  |  50–60: 1.24  |  60+: 1.36
        let ageFactor: Double
        if settings.profileComplete {
            switch settings.ageYears {
            case ..<20:    ageFactor = 0.90
            case 20..<30:  ageFactor = 1.00
            case 30..<40:  ageFactor = 1.06
            case 40..<50:  ageFactor = 1.14
            case 50..<60:  ageFactor = 1.24
            default:       ageFactor = 1.36
            }
        } else {
            ageFactor = 1.0
        }

        // ── Intensity bonus ──────────────────────────────────────────────────
        // Compares actual speed to the "comfortable" speed for the workout type.
        // > 20 % above comfortable → 1.15 bonus
        let comfortableSpeedMPS: Double
        switch workoutType {
        case .running: comfortableSpeedMPS = 3.0   // ~11 km/h
        case .walking: comfortableSpeedMPS = 1.3   // ~5 km/h
        case .cycling: comfortableSpeedMPS = 5.0   // ~18 km/h
        case .hiking:  comfortableSpeedMPS = 1.0   // ~3.6 km/h
        default:       comfortableSpeedMPS = 1.5   // non-distance activities
        }

        let intensityBonus: Double
        if averageSpeedMPS > 0 && durationSeconds > 60 {
            let ratio = averageSpeedMPS / comfortableSpeedMPS
            switch ratio {
            case ..<0.70:  intensityBonus = 0.85   // very slow
            case 0.70..<0.90: intensityBonus = 0.95
            case 0.90..<1.10: intensityBonus = 1.00
            case 1.10..<1.25: intensityBonus = 1.08
            default:       intensityBonus = 1.15   // fast / hard effort
            }
        } else {
            intensityBonus = 1.0
        }

        // ── Base components ──────────────────────────────────────────────────
        let caloriePoints  = calories * 1.5
        let distancePoints = distanceKm * distanceFactor
        let durationPoints = durationMin * 0.4

        let base  = caloriePoints + distancePoints + durationPoints
        let raw   = base * ageFactor * intensityBonus

        // ── Grade thresholds ─────────────────────────────────────────────────
        // calibrated so a solid 5 km run ≈ B (400–600 pts)
        let grade: Grade
        switch raw {
        case 800...:   grade = .s
        case 550..<800: grade = .a
        case 350..<550: grade = .b
        case 150..<350: grade = .c
        default:        grade = .d
        }

        let breakdown = Breakdown(
            caloriePoints:  caloriePoints,
            distancePoints: distancePoints,
            durationPoints: durationPoints,
            ageFactor:      ageFactor,
            bmiLabel:       settings.profileComplete ? settings.bmiCategory.label : "–",
            distanceFactor: distanceFactor,
            intensityBonus: intensityBonus
        )

        return WorkoutScore(
            rawScore:     raw,
            displayScore: Int(raw.rounded()),
            grade:        grade,
            breakdown:    breakdown
        )
    }
}

extension WorkoutRecord {
    func score(settings: UserSettings) -> WorkoutScore {
        WorkoutScore.calculate(
            calories:         activeCalories,
            distanceMeters:   distanceMeters,
            durationSeconds:  duration,
            averageSpeedMPS:  averageSpeedMPS,
            workoutType:      workoutType,
            settings:         settings
        )
    }
}
