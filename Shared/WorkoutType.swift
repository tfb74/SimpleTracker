import Foundation
import HealthKit

enum WorkoutType: String, CaseIterable, Codable, Identifiable {
    case running
    case walking
    case cycling
    case hiking
    case swimming
    case rowing
    case elliptical
    case stairs
    case yoga
    case strength
    case hiit
    case dance
    case tennis
    case soccer
    case basketball
    case golf
    case skating
    case skiing
    // Leichte Aktivitäten — werden im Picker farblich abgesetzt
    case eBike
    case gardening
    case other

    var id: String { rawValue }

    /// Kategorie zur visuellen Gruppierung im Picker.
    /// `light` = entspannte Aktivität (Gehen, E-Bike, Gartenarbeit)
    /// `standard` = klassisches Training
    enum Category {
        case standard
        case light
    }

    var category: Category {
        switch self {
        case .walking, .eBike, .gardening: return .light
        default: return .standard
        }
    }

    var displayName: String {
        switch self {
        case .running: return lt("Laufen")
        case .walking: return lt("Gehen")
        case .cycling: return lt("Radfahren")
        case .hiking: return lt("Wandern")
        case .swimming: return lt("Schwimmen")
        case .rowing: return lt("Rudern")
        case .elliptical: return lt("Crosstrainer")
        case .stairs: return lt("Treppen")
        case .yoga: return lt("Yoga")
        case .strength: return lt("Krafttraining")
        case .hiit: return "HIIT"
        case .dance: return lt("Tanzen")
        case .tennis: return "Tennis"
        case .soccer: return lt("Fußball")
        case .basketball: return "Basketball"
        case .golf: return "Golf"
        case .skating: return lt("Skaten")
        case .skiing: return lt("Ski")
        case .eBike: return lt("E-Bike")
        case .gardening: return lt("Gartenarbeit")
        case .other: return lt("Sonstiges")
        }
    }

    var systemImage: String {
        switch self {
        case .running: return "figure.run"
        case .walking: return "figure.walk"
        case .cycling: return "figure.outdoor.cycle"
        case .hiking: return "figure.hiking"
        case .swimming: return "figure.pool.swim"
        case .rowing: return "figure.rower"
        case .elliptical: return "figure.elliptical"
        case .stairs: return "figure.stairs"
        case .yoga: return "figure.yoga"
        case .strength: return "figure.strengthtraining.traditional"
        case .hiit: return "figure.highintensity.intervaltraining"
        case .dance: return "figure.dance"
        case .tennis: return "figure.tennis"
        case .soccer: return "figure.soccer"
        case .basketball: return "figure.basketball"
        case .golf: return "figure.golf"
        case .skating: return "figure.skating"
        case .skiing: return "figure.skiing.downhill"
        case .eBike: return "bicycle"
        case .gardening: return "leaf.fill"
        case .other: return "figure.mixed.cardio"
        }
    }

    var hkWorkoutActivityType: HKWorkoutActivityType {
        switch self {
        case .running: return .running
        case .walking: return .walking
        case .cycling: return .cycling
        case .hiking: return .hiking
        case .swimming: return .swimming
        case .rowing: return .rowing
        case .elliptical: return .elliptical
        case .stairs: return .stairClimbing
        case .yoga: return .yoga
        case .strength: return .traditionalStrengthTraining
        case .hiit: return .highIntensityIntervalTraining
        case .dance: return .cardioDance
        case .tennis: return .tennis
        case .soccer: return .soccer
        case .basketball: return .basketball
        case .golf: return .golf
        case .skating: return .skatingSports
        case .skiing: return .downhillSkiing
        case .eBike: return .cycling
        case .gardening: return .other
        case .other: return .other
        }
    }
}
