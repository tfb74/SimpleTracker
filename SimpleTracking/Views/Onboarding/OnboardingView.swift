import SwiftUI

/// Erstes-Mal-Onboarding. Wird beim ersten App-Start gezeigt und führt
/// Schritt-für-Schritt durch die wichtigsten Features. Vollständig
/// lokalisiert über lt().
struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool

    @State private var currentPage: Int = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            iconName: "figure.run",
            tint: .green,
            titleKey: "Willkommen bei SimpleTracking",
            subtitleKey: "Workouts, Ernährung und Schritte – alles in einer App."
        ),
        OnboardingPage(
            iconName: "map.fill",
            tint: .blue,
            titleKey: "Workouts mit GPS",
            subtitleKey: "Starte Laufen, Radfahren oder Wandern mit Live-Karte. Indoor-Aktivitäten kannst du manuell eintragen."
        ),
        OnboardingPage(
            iconName: "fork.knife",
            tint: .orange,
            titleKey: "Ernährung dokumentieren",
            subtitleKey: "Mahlzeiten per Foto erkennen lassen, Barcode scannen oder manuell eingeben. Mit BE-Berechnung."
        ),
        OnboardingPage(
            iconName: "person.2.fill",
            tint: .purple,
            titleKey: "Mit Freunden teilen",
            subtitleKey: "Tausche deinen Code aus, sieh ihre Aktivitäten und feure sie an – oder rooste sie."
        ),
        OnboardingPage(
            iconName: "heart.fill",
            tint: .red,
            titleKey: "Privat und auf deinem Gerät",
            subtitleKey: "Foto-Analyse läuft lokal mit Apple Intelligence. Deine Daten bleiben deine Daten."
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                ForEach(pages.indices, id: \.self) { index in
                    OnboardingPageView(page: pages[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            VStack(spacing: 12) {
                Button {
                    withAnimation {
                        if currentPage < pages.count - 1 {
                            currentPage += 1
                        } else {
                            complete()
                        }
                    }
                } label: {
                    Text(currentPage < pages.count - 1 ? lt("Weiter") : lt("Loslegen"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)

                if currentPage < pages.count - 1 {
                    Button(lt("Überspringen")) {
                        complete()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 32)
        }
    }

    private func complete() {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation {
            hasCompletedOnboarding = true
        }
    }
}

private struct OnboardingPage {
    let iconName: String
    let tint: Color
    let titleKey: String
    let subtitleKey: String
}

private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            ZStack {
                Circle()
                    .fill(page.tint.opacity(0.15))
                    .frame(width: 160, height: 160)
                Image(systemName: page.iconName)
                    .font(.system(size: 72, weight: .medium))
                    .foregroundStyle(page.tint)
            }

            VStack(spacing: 12) {
                Text(lt(page.titleKey))
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Text(lt(page.subtitleKey))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()
            Spacer()
        }
    }
}

// MARK: - Helper für ContentView

extension UserDefaults {
    private static let onboardingKey = "hasCompletedOnboarding.v1"
    var hasCompletedOnboarding: Bool {
        get { bool(forKey: Self.onboardingKey) }
        set { set(newValue, forKey: Self.onboardingKey) }
    }
}
