import SwiftUI

struct ImportView: View {
    @Environment(HealthKitService.self) private var healthKit
    @State private var isImporting = false
    @State private var importDone  = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                Image(systemName: "square.and.arrow.down.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentColor)

                VStack(spacing: 10) {
                    Text("Apple Health importieren")
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)

                    Text("Alle Workouts, Schritte, Kalorien und Routen aus Apple Health werden geladen – inklusive aller Apple Watch-Aufzeichnungen.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                if importDone {
                    Label("\(healthKit.workouts.count) Workouts geladen", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline.bold())
                        .transition(.scale.combined(with: .opacity))
                }

                Button(action: runImport) {
                    Group {
                        if isImporting {
                            HStack(spacing: 8) {
                                ProgressView().tint(.white)
                                Text("Importiere…")
                            }
                        } else {
                            Text(importDone ? "Erneut importieren" : "Jetzt importieren")
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(isImporting)
                .padding(.horizontal, 24)

                Spacer()
            }
            .navigationTitle("Importieren")
            .animation(.spring, value: importDone)
        }
    }

    private func runImport() {
        Task {
            isImporting = true
            await healthKit.fullImportFromHealth()
            isImporting = false
            withAnimation { importDone = true }
        }
    }
}
