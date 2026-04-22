import SwiftUI
import UIKit

#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

/// SwiftUI-Wrapper um eine AdMob-Native-Ad — optisch dem `MetricTile` in
/// der Statistik nachempfunden, damit sich die Werbung visuell einfügt.
///
/// Falls das AdMob-SDK noch nicht aufgelöst wurde (z. B. beim ersten
/// Build oder auf CI ohne Netz), wird still nichts angezeigt. Ebenfalls
/// nichts, wenn AdMob aktuell keinen Fill liefert.
struct NativeAdTile: View {
    var body: some View {
        #if DEBUG && targetEnvironment(simulator)
        SimulatorNativeAdPreviewTile()
            .padding(.horizontal)
        #elseif canImport(GoogleMobileAds)
        NativeAdContainer()
        #else
        EmptyView()
        #endif
    }
}

#if canImport(GoogleMobileAds)

// MARK: - Container (lädt die Ad, rendert sie wenn da)

private struct NativeAdContainer: View {
    @State private var nativeAd: GADNativeAd?
    @State private var loader = NativeAdLoaderHolder()
    @State private var hasRequestedAd = false

    var body: some View {
        Group {
            if let ad = nativeAd {
                NativeAdTileRepresentable(nativeAd: ad)
                    .frame(height: 92)
                    .padding(.horizontal)
            } else {
                EmptyView()
            }
        }
        .onAppear {
            guard !hasRequestedAd else { return }
            hasRequestedAd = true
            loader.load { ad in
                self.nativeAd = ad
            }
        }
    }
}

// MARK: - AdLoader-Halter

/// Eigener Objekt-Halter, damit der Delegate nicht aus dem Speicher fällt.
private final class NativeAdLoaderHolder: NSObject, GADNativeAdLoaderDelegate {
    private var loader: GADAdLoader?
    private var onLoad: ((GADNativeAd) -> Void)?

    @MainActor
    func load(onLoad: @escaping (GADNativeAd) -> Void) {
        guard AdService.shared.isReady else {
            // SDK noch nicht bootstrap'd → 0,5 s warten und erneut versuchen
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                Task { @MainActor in
                    self.load(onLoad: onLoad)
                }
            }
            return
        }
        self.onLoad = onLoad
        let root = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }
            .first
        let options = GADNativeAdViewAdOptions()
        let loader = GADAdLoader(
            adUnitID: AdService.shared.nativeAdUnitID,
            rootViewController: root,
            adTypes: [GADAdLoaderAdType.native],
            options: [options]
        )
        loader.delegate = self
        loader.load(GADRequest())
        self.loader = loader
    }

    func adLoader(_ adLoader: GADAdLoader, didReceive nativeAd: GADNativeAd) {
        onLoad?(nativeAd)
    }

    func adLoader(_ adLoader: GADAdLoader, didFailToReceiveAdWithError error: Error) {
        print("[Ads] Native ad failed: \(error.localizedDescription)")
    }
}

// MARK: - UIKit-Bridge — zeigt die Native-Ad im MetricTile-Stil

private struct NativeAdTileRepresentable: UIViewRepresentable {
    let nativeAd: GADNativeAd

    func makeUIView(context: Context) -> GADNativeAdView {
        let view = GADNativeAdView()
        view.backgroundColor = .secondarySystemBackground
        view.layer.cornerRadius = 10
        view.layer.masksToBounds = true
        view.translatesAutoresizingMaskIntoConstraints = false

        // --- Subviews ---

        let badge = UILabel()
        badge.text = "Gesponsert"
        badge.font = .systemFont(ofSize: 10, weight: .semibold)
        badge.textColor = .secondaryLabel
        badge.translatesAutoresizingMaskIntoConstraints = false

        let icon = UIImageView()
        icon.contentMode = .scaleAspectFit
        icon.layer.cornerRadius = 6
        icon.layer.masksToBounds = true
        icon.translatesAutoresizingMaskIntoConstraints = false

        let headline = UILabel()
        headline.font = .systemFont(ofSize: 17, weight: .semibold)
        headline.textColor = .label
        headline.numberOfLines = 1
        headline.translatesAutoresizingMaskIntoConstraints = false

        let body = UILabel()
        body.font = .systemFont(ofSize: 12, weight: .regular)
        body.textColor = .secondaryLabel
        body.numberOfLines = 2
        body.translatesAutoresizingMaskIntoConstraints = false

        let cta = UILabel()
        cta.font = .systemFont(ofSize: 12, weight: .semibold)
        cta.textColor = .tintColor
        cta.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(badge)
        view.addSubview(icon)
        view.addSubview(headline)
        view.addSubview(body)
        view.addSubview(cta)

        // --- Constraints ---

        NSLayoutConstraint.activate([
            badge.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            badge.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),

            icon.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 6),
            icon.widthAnchor.constraint(equalToConstant: 44),
            icon.heightAnchor.constraint(equalToConstant: 44),

            headline.topAnchor.constraint(equalTo: badge.bottomAnchor, constant: 4),
            headline.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            headline.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -10),

            body.topAnchor.constraint(equalTo: headline.bottomAnchor, constant: 2),
            body.leadingAnchor.constraint(equalTo: headline.leadingAnchor),
            body.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -10),

            cta.topAnchor.constraint(equalTo: body.bottomAnchor, constant: 4),
            cta.leadingAnchor.constraint(equalTo: headline.leadingAnchor),
            cta.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -8)
        ])

        // --- AdMob-Verdrahtung ---
        view.iconView = icon
        view.headlineView = headline
        view.bodyView = body
        view.callToActionView = cta

        return view
    }

    func updateUIView(_ view: GADNativeAdView, context: Context) {
        view.nativeAd = nativeAd
        (view.headlineView as? UILabel)?.text = nativeAd.headline
        (view.bodyView as? UILabel)?.text = nativeAd.body
        (view.iconView as? UIImageView)?.image = nativeAd.icon?.image
        (view.callToActionView as? UILabel)?.text = (nativeAd.callToAction ?? "Mehr erfahren") + "  ›"
        // CTA muss non-interactive sein — AdMob fängt Taps selbst ab.
        view.callToActionView?.isUserInteractionEnabled = false
    }
}

private struct SimulatorNativeAdPreviewTile: View {
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Gesponsert")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.orange.opacity(0.18))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "megaphone.fill")
                                .foregroundStyle(.orange)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Ad Preview")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("Simulator-Fallback fuer die Platzierung")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Mehr erfahren  ›")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tint)
                    }
                    Spacer(minLength: 0)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

#endif
