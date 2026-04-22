import SwiftUI

struct WorkoutHistoryView: View {
    @Environment(HealthKitService.self) private var healthKit

    private var grouped: [(key: String, workouts: [WorkoutRecord])] {
        let fmt = DateFormatter(); fmt.dateStyle = .medium
        let dict = Dictionary(grouping: healthKit.workouts) { fmt.string(from: $0.startDate) }
        return dict.map { (key: $0.key, workouts: $0.value) }
                   .sorted { $0.workouts.first!.startDate > $1.workouts.first!.startDate }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(grouped, id: \.key) { group in
                    Section(group.key) {
                        ForEach(group.workouts) { workout in
                            NavigationLink(destination: WorkoutDetailView(workout: workout)) {
                                WorkoutRowView(workout: workout)
                            }
                            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    Task { await healthKit.deleteWorkout(workout) }
                                } label: {
                                    Label("Löschen", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Verlauf")
            .overlay {
                if healthKit.isLoading {
                    ProgressView("Lade…")
                } else if healthKit.workouts.isEmpty {
                    ContentUnavailableView(
                        "Keine Workouts",
                        systemImage: "figure.walk",
                        description: Text("Starte dein erstes Workout oder importiere Daten aus Apple Health.")
                    )
                }
            }
            .refreshable { await healthKit.loadWorkouts() }
        }
    }
}
