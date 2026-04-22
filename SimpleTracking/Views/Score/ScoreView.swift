import SwiftUI

/// Großes Score-Display für Workout-Detail und Dashboard.
struct ScoreBadge: View {
    let score: WorkoutScore

    private var gradeColor: Color {
        switch score.grade {
        case .s: return .yellow
        case .a: return .green
        case .b: return .blue
        case .c: return .orange
        case .d: return .red
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(gradeColor.opacity(0.2), lineWidth: 6)
                    .frame(width: 80, height: 80)
                Circle()
                    .trim(from: 0, to: min(CGFloat(score.displayScore) / 1_000, 1.0))
                    .stroke(gradeColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 80, height: 80)
                VStack(spacing: 0) {
                    Text("\(score.displayScore)")
                        .font(.title3.bold().monospacedDigit())
                    Text("Pkt.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Text("Bewertung \(score.grade.rawValue)")
                .font(.caption.bold())
                .foregroundStyle(gradeColor)
        }
    }
}

/// Kleine Score-Pille für Listen / Karten.
struct ScorePill: View {
    let score: WorkoutScore

    private var color: Color {
        switch score.grade {
        case .s: return .yellow
        case .a: return .green
        case .b: return .blue
        case .c: return .orange
        case .d: return .red
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(score.grade.rawValue)
                .font(.caption2.bold())
            Text("\(score.displayScore)")
                .font(.caption2.monospacedDigit())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.15))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }
}

/// Aufklappbare Score-Breakdown Sektion für WorkoutDetailView.
struct ScoreBreakdownView: View {
    let score: WorkoutScore
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(duration: 0.3)) { expanded.toggle() }
            } label: {
                HStack {
                    ScoreBadge(score: score)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Fitness-Score")
                            .font(.headline)
                        Text("Berechnung anzeigen")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(spacing: 8) {
                    breakdownRow("Kalorien-Punkte",
                                 value: score.breakdown.caloriePoints,
                                 icon: "flame.fill", color: .orange)
                    breakdownRow("Distanz-Punkte (\(score.breakdown.bmiLabel), Faktor ×\(String(format: "%.0f", score.breakdown.distanceFactor)))",
                                 value: score.breakdown.distancePoints,
                                 icon: "map.fill", color: .blue)
                    breakdownRow("Dauer-Punkte",
                                 value: score.breakdown.durationPoints,
                                 icon: "timer", color: .purple)

                    Divider()

                    factorRow("Alters-Faktor",
                              value: score.breakdown.ageFactor,
                              icon: "person.fill")
                    factorRow("Intensitäts-Bonus",
                              value: score.breakdown.intensityBonus,
                              icon: "bolt.fill")

                    Divider()

                    HStack {
                        Text("Gesamt-Score")
                            .font(.subheadline.bold())
                        Spacer()
                        Text("\(score.displayScore) Punkte")
                            .font(.subheadline.bold().monospacedDigit())
                    }
                }
                .padding()
                .background(.regularMaterial.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.top, 2)
            }
        }
    }

    private func breakdownRow(_ label: String, value: Double, icon: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(color).frame(width: 20)
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(String(format: "+ %.0f", value))
                .font(.caption.monospacedDigit().bold())
        }
    }

    private func factorRow(_ label: String, value: Double, icon: String) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(.secondary).frame(width: 20)
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(String(format: "× %.2f", value))
                .font(.caption.monospacedDigit())
        }
    }
}
