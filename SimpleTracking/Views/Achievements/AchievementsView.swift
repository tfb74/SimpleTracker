import SwiftUI

struct AchievementsView: View {
    @Environment(GameCenterService.self) private var gameCenter
    @Environment(HealthKitService.self)  private var healthKit
    @Environment(UserSettings.self)      private var settings

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                summaryHeader
                    .padding(.horizontal)
                    .padding(.top, 8)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Achievement.allCases, id: \.rawValue) { achievement in
                        AchievementCard(
                            achievement: achievement,
                            isUnlocked: gameCenter.unlockedAchievements.contains(achievement)
                        )
                    }
                }
                .padding()

                if settings.gameCenterSyncEnabled && gameCenter.isAuthenticated {
                    HStack(spacing: 12) {
                        Button { gameCenter.showLeaderboards() } label: {
                            Label("Bestenlisten", systemImage: "list.number")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button { gameCenter.showAchievements() } label: {
                            Label("Game Center", systemImage: "gamecontroller.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
            .navigationTitle("Erfolge")
            .task {
                gameCenter.evaluateAchievements(for: healthKit.workouts,
                                                todaySteps: healthKit.todaySteps,
                                                settings: settings)
                if settings.gameCenterSyncEnabled && !gameCenter.isAuthenticated {
                    await gameCenter.authenticate()
                }
            }
        }
    }

    private var summaryHeader: some View {
        HStack(spacing: 12) {
            if settings.gameCenterSyncEnabled && gameCenter.isAuthenticated,
               let img = gameCenter.playerAvatar {
                Image(uiImage: img).resizable().scaledToFill()
                    .frame(width: 48, height: 48).clipShape(Circle())
            } else {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 48, height: 48)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(Circle())
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(settings.gameCenterSyncEnabled && gameCenter.isAuthenticated
                     ? gameCenter.playerName
                     : "Erfolge")
                    .font(.headline)
                Text("\(gameCenter.unlockedAchievements.count) / \(Achievement.allCases.count) freigeschaltet")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if settings.gameCenterSyncEnabled && gameCenter.isAuthenticated {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

}

struct AchievementCard: View {
    let achievement: Achievement
    let isUnlocked: Bool

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: achievement.icon)
                .font(.system(size: 32))
                .foregroundStyle(isUnlocked ? Color.accentColor : Color.secondary.opacity(0.4))

            Text(achievement.displayName)
                .font(.caption.bold())
                .multilineTextAlignment(.center)

            Text(achievement.description)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(isUnlocked ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isUnlocked ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .grayscale(isUnlocked ? 0 : 0.6)
    }
}
