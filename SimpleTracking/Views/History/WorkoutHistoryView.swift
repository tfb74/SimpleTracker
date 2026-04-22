import SwiftUI

struct WorkoutHistoryView: View {
    @Environment(HealthKitService.self) private var healthKit

    @State private var isImporting = false
    @State private var showImportDone = false

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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await runImport() }
                    } label: {
                        if isImporting {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Image(systemName: "square.and.arrow.down")
                        }
                    }
                    .disabled(isImporting)
                    .accessibilityLabel("Von Apple Health laden")
                }
            }
            .overlay {
                if healthKit.isLoading {
                    ProgressView("Lade…")
                } else if healthKit.workouts.isEmpty {
                    emptyState
                }
            }
            .refreshable { await healthKit.loadWorkouts() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "figure.walk")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("Keine Workouts")
                    .font(.title3.bold())
                Text("Starte dein erstes Workout oder lade deine Daten aus Apple Health – inklusive Apple Watch-Aufzeichnungen.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                Task { await runImport() }
            } label: {
                Group {
                    if isImporting {
                        HStack(spacing: 6) {
                            ProgressView().tint(.white)
                            Text("Importiere…")
                        }
                    } else if showImportDone {
                        Label("Geladen", systemImage: "checkmark")
                    } else {
                        Label("Von Apple Health laden", systemImage: "square.and.arrow.down")
                    }
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isImporting)
            .animation(.spring, value: showImportDone)
        }
    }

    private func runImport() async {
        guard !isImporting else { return }
        isImporting = true
        showImportDone = false
        await healthKit.fullImportFromHealth()
        isImporting = false
        withAnimation { showImportDone = true }
    }
}
