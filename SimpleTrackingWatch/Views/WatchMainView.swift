import SwiftUI

struct WatchMainView: View {
    @Environment(WatchWorkoutService.self) private var workoutService

    var body: some View {
        if workoutService.isActive {
            WatchActiveWorkoutView()
        } else {
            NavigationStack {
                List(WorkoutType.allCases) { type in
                    Button {
                        Task {
                            try? await workoutService.requestAuthorization()
                            try? await workoutService.startWorkout(type: type)
                        }
                    } label: {
                        Label(type.displayName, systemImage: type.systemImage)
                    }
                }
                .navigationTitle(lt("SimpleTracking"))
            }
        }
    }
}
