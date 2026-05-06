import Foundation

struct CustomSport: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var symbol: String

    init(id: UUID = UUID(), name: String, symbol: String = "figure.mixed.cardio") {
        self.id = id
        self.name = name
        self.symbol = symbol
    }
}

/// Speichert benutzerdefinierte GPS-trackbare Sportarten in UserDefaults.
@Observable
final class CustomSportStore {
    static let shared = CustomSportStore()

    private let key = "CustomSportStore.sports.v1"
    private(set) var sports: [CustomSport] = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([CustomSport].self, from: data) {
            sports = decoded
        }
    }

    func add(name: String, symbol: String = "figure.mixed.cardio") {
        let sport = CustomSport(name: name.trimmingCharacters(in: .whitespaces), symbol: symbol)
        sports.append(sport)
        save()
    }

    func remove(_ sport: CustomSport) {
        sports.removeAll { $0.id == sport.id }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(sports) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    // Symbol-Auswahl für benutzerdefinierte Sportarten
    static let symbolChoices: [String] = [
        "figure.mixed.cardio",
        "figure.strengthtraining.traditional",
        "figure.highintensity.intervaltraining",
        "figure.climbing",
        "figure.boxing",
        "figure.martial.arts",
        "figure.kickboxing",
        "figure.jumprope",
        "figure.archery",
        "figure.bowling",
        "figure.disc.sports",
        "figure.equestrian.sports",
        "figure.fishing",
        "figure.gymnastics",
        "figure.handball",
        "figure.lacrosse",
        "figure.pickleball",
        "figure.rugby",
        "figure.volleyball",
        "figure.water.fitness",
        "figure.cross.training",
        "dumbbell.fill",
        "sportscourt.fill",
        "trophy.fill",
        "medal.fill",
    ]
}
