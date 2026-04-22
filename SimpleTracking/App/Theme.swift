import SwiftUI
import UIKit

enum Theme {
    static let anthraciteBase = UIColor(red: 30/255,  green: 32/255,  blue: 36/255,  alpha: 1)
    static let anthraciteGrouped = UIColor(red: 22/255,  green: 24/255,  blue: 28/255,  alpha: 1)
    static let anthraciteElevated = UIColor(red: 42/255,  green: 45/255,  blue: 50/255,  alpha: 1)
    static let anthraciteSeparator = UIColor(red: 60/255,  green: 63/255,  blue: 68/255,  alpha: 1)

    private static func dynamic(dark: UIColor, light: UIColor) -> UIColor {
        UIColor { trait in trait.userInterfaceStyle == .dark ? dark : light }
    }

    static func applyAppearance() {
        let bg        = dynamic(dark: anthraciteBase,      light: .systemBackground)
        let grouped   = dynamic(dark: anthraciteGrouped,   light: .systemGroupedBackground)
        let elevated  = dynamic(dark: anthraciteElevated,  light: .secondarySystemGroupedBackground)
        let separator = dynamic(dark: anthraciteSeparator, light: .separator)

        let table = UITableView.appearance()
        table.backgroundColor = grouped
        table.separatorColor  = separator

        UITableViewCell.appearance().backgroundColor = elevated
        UICollectionView.appearance().backgroundColor = grouped

        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = bg
        UINavigationBar.appearance().standardAppearance   = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance    = nav

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = bg
        UITabBar.appearance().standardAppearance   = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }
}

extension Color {
    static let anthraciteBase     = Color(uiColor: Theme.anthraciteBase)
    static let anthraciteGrouped  = Color(uiColor: Theme.anthraciteGrouped)
    static let anthraciteElevated = Color(uiColor: Theme.anthraciteElevated)
}

struct AppHeaderMetric: Identifiable {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var id: String { "\(title)-\(value)-\(systemImage)" }
}

struct AppChromeActionLabel: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.headline.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: 42, height: 42)
            .background(.thinMaterial, in: Circle())
            .overlay {
                Circle()
                    .strokeBorder(tint.opacity(0.18), lineWidth: 1)
            }
    }
}

extension ProfileAvatarPreset {
    var gradientColors: [Color] {
        switch self {
        case .person: return [Color.blue, Color.cyan]
        case .walker: return [Color.teal, Color.green]
        case .runner: return [Color.orange, Color.pink]
        case .cyclist: return [Color.indigo, Color.blue]
        case .swimmer: return [Color.cyan, Color.mint]
        case .hiker: return [Color.brown, Color.green]
        case .strength: return [Color.red, Color.orange]
        case .tennis: return [Color.yellow, Color.green]
        case .soccer: return [Color.green, Color.black.opacity(0.7)]
        case .leaf: return [Color.green, Color.mint]
        case .heart: return [Color.red, Color.orange]
        case .sparkles: return [Color.indigo, Color.teal]
        }
    }

    var accentColor: Color {
        gradientColors.first ?? .accentColor
    }
}

struct UserAvatarView: View {
    let size: CGFloat
    let name: String
    let photoData: Data?
    let preset: ProfileAvatarPreset
    let fallbackImage: UIImage?

    private var resolvedImage: UIImage? {
        if let photoData, let image = UIImage(data: photoData) {
            return image
        }
        return fallbackImage
    }

    private var initials: String {
        let parts = name
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }

        return String(parts).uppercased()
    }

    var body: some View {
        ZStack {
            if let resolvedImage {
                Image(uiImage: resolvedImage)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(colors: preset.gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)

                VStack(spacing: size >= 54 ? 4 : 0) {
                    Image(systemName: preset.systemImage)
                        .font(.system(size: size * 0.36, weight: .semibold))
                        .foregroundStyle(.white)

                    if size >= 54, !initials.isEmpty {
                        Text(initials)
                            .font(.system(size: size * 0.18, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.92))
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle()
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: size * 0.12, y: size * 0.06)
    }
}

private struct AppChromeHeader<Accessory: View>: View {
    @Environment(UserSettings.self)      private var settings
    @Environment(GameCenterService.self) private var gameCenter
    @Environment(CloudKitService.self)   private var cloudKit

    @State private var showFriends = false

    let title: String
    let accent: Color
    let metrics: [AppHeaderMetric]
    let accessory: () -> Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .lineLimit(1)

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 6) {
                    Text(displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HStack(spacing: 10) {
                        accessory()
                        avatar
                    }
                }
            }

            if !metrics.isEmpty {
                HStack(spacing: 10) {
                    ForEach(Array(metrics.prefix(2))) { metric in
                        AppChromeMetricChip(metric: metric)
                    }
                }
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    accent.opacity(0.22),
                                    accent.opacity(0.07),
                                    Color.white.opacity(0.10)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(accent.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: accent.opacity(0.10), radius: 18, y: 10)
    }

    @ViewBuilder
    private var avatar: some View {
        Button { showFriends = true } label: {
            ZStack(alignment: .bottomTrailing) {
                UserAvatarView(
                    size: 42,
                    name: displayName,
                    photoData: settings.avatarImageData,
                    preset: settings.avatarPreset,
                    fallbackImage: gameCenter.isAuthenticated ? gameCenter.playerAvatar : nil
                )
                .overlay(alignment: .topTrailing) {
                    if cloudKit.unreadCount > 0 {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 11, height: 11)
                            .overlay { Circle().strokeBorder(.background, lineWidth: 2) }
                            .offset(x: 3, y: -3)
                    }
                }

                Circle()
                    .fill(gameCenter.isAuthenticated ? Color.green : Color.secondary.opacity(0.5))
                    .frame(width: 10, height: 10)
                    .overlay {
                        Circle().strokeBorder(.background, lineWidth: 2)
                    }
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showFriends) {
            FriendsView()
        }
    }

    private var displayName: String {
        let gameCenterName = gameCenter.isAuthenticated ? gameCenter.playerName : ""
        return settings.effectiveProfileName(fallbackName: suggestedDeviceName(preferred: gameCenterName))
    }

    private func suggestedDeviceName(preferred: String) -> String {
        if !preferred.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return preferred
        }
        return UIDevice.current.name
    }
}

private struct AppChromeMetricChip: View {
    let metric: AppHeaderMetric

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: metric.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(metric.tint)
                .frame(width: 28, height: 28)
                .background(metric.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(metric.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(metric.value)
                    .font(.subheadline.monospacedDigit().weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct AppChromeModifier<Accessory: View>: ViewModifier {
    let title: String
    let accent: Color
    let metrics: [AppHeaderMetric]
    let accessory: () -> Accessory

    func body(content: Content) -> some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                AppChromeHeader(title: title, accent: accent, metrics: metrics, accessory: accessory)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
            }
    }
}

extension View {
    func appChrome(title: String, accent: Color, metrics: [AppHeaderMetric]) -> some View {
        modifier(AppChromeModifier(title: title, accent: accent, metrics: metrics) {
            EmptyView()
        })
    }

    func appChrome<Accessory: View>(
        title: String,
        accent: Color,
        metrics: [AppHeaderMetric],
        @ViewBuilder accessory: @escaping () -> Accessory
    ) -> some View {
        modifier(AppChromeModifier(title: title, accent: accent, metrics: metrics, accessory: accessory))
    }
}

extension UIImage {
    func preparedAvatarData(maxDimension: CGFloat = 600, compressionQuality: CGFloat = 0.82) -> Data? {
        let longestSide = max(size.width, size.height)
        guard longestSide > 0 else { return jpegData(compressionQuality: compressionQuality) }

        let scale = min(1, maxDimension / longestSide)
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let image = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }

        return image.jpegData(compressionQuality: compressionQuality)
    }
}
