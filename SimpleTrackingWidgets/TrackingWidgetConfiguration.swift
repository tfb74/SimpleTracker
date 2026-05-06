import AppIntents
import WidgetKit

enum TrackingWidgetScene: String, AppEnum {
    case automatic
    case overview
    case activity
    case energy
    case nutrition
    case workouts
    case distance

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Widget-Szene")

    static var caseDisplayRepresentations: [TrackingWidgetScene: DisplayRepresentation] = [
        .automatic: DisplayRepresentation(title: "Automatisch"),
        .overview: DisplayRepresentation(title: "Heute Überblick"),
        .activity: DisplayRepresentation(title: "Aktivität"),
        .energy: DisplayRepresentation(title: "Energie-Bilanz"),
        .nutrition: DisplayRepresentation(title: "Ernährung"),
        .workouts: DisplayRepresentation(title: "Workouts"),
        .distance: DisplayRepresentation(title: "Distanz")
    ]
}

struct TrackingWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "SimpleTracking"
    static var description = IntentDescription("Wähle, welche Statistik im Widget angezeigt wird, wenn kein Workout läuft.")

    @Parameter(title: "Szene", default: .automatic)
    var scene: TrackingWidgetScene

    static var parameterSummary: some ParameterSummary {
        Summary("Zeige \(\.$scene)")
    }
}
