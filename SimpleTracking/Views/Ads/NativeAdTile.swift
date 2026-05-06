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

#if DEBUG && canImport(GoogleMobileAds)
/// Sichtbares Debug-Placeholder fürs reale iPhone, damit man im Build sehen
/// kann ob/warum keine Ad geladen wurde. Nicht in Release-Builds enthalten.
private struct DebugAdLoadStatusTile: View {
    let status: String
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "ladybug.fill").foregroundStyle(.orange)
                Text("AdMob Debug").font(.caption.weight(.semibold))
                Spacer()
                Text(status).font(.caption2).foregroundStyle(.secondary)
            }
            if let error {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            } else {
                Text("Test-Ad wird geladen…")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Text("UMP: \(AdService.shared.diag_umpStatus)")
                Text("ATT: \(AdService.shared.diag_attStatus)")
                Text("SDK: \(AdService.shared.diag_sdkStarted ? "✓" : "…")")
            }
            .font(.caption2.monospaced())
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.orange.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
    }
}
#endif

#if canImport(GoogleMobileAds)

// MARK: - Container (lädt die Ad, rendert sie wenn da)

private struct NativeAdContainer: View {
    @State private var nativeAd: GADNativeAd?
    @State private var loader = NativeAdLoaderHolder()
    @State private var hasRequestedAd = false
    @State private var loadError: String?
    @State private var retryCount = 0

    var body: some View {
        Group {
            if let ad = nativeAd {
                NativeAdTileRepresentable(nativeAd: ad)
                    .frame(height: 96)
                    .padding(.horizontal)
            } else {
                #if DEBUG
                DebugAdLoadStatusTile(
                    status: hasRequestedAd ? "lädt… (Retry \(retryCount))" : "wartet auf SDK",
                    error: loadError
                )
                #else
                EmptyView()
                #endif
            }
        }
        .onAppear {
            guard !hasRequestedAd else { return }
            hasRequestedAd = true
            requestAd()
        }
    }

    private func requestAd() {
        loader.load(
            onLoad: { ad in
                self.nativeAd = ad
                self.loadError = nil
                AdService.shared.recordNativeAdResult(error: nil)
                print("[Ads] ✅ Native ad loaded")
            },
            onError: { msg in
                self.loadError = msg
                AdService.shared.recordNativeAdResult(error: msg)
                print("[Ads] ❌ Native ad failed: \(msg)")
                // Bei No-Fill nach 5s erneut versuchen, max. 3x
                if self.retryCount < 3 {
                    let delay: TimeInterval = 5 * Double(self.retryCount + 1)
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        self.retryCount += 1
                        self.requestAd()
                    }
                }
            }
        )
    }
}

// MARK: - AdLoader-Halter

/// Eigener Objekt-Halter, damit der Delegate nicht aus dem Speicher fällt.
private final class NativeAdLoaderHolder: NSObject, GADNativeAdLoaderDelegate {
    private var loader: GADAdLoader?
    private var onLoad: ((GADNativeAd) -> Void)?
    private var onError: ((String) -> Void)?

    @MainActor
    func load(onLoad: @escaping (GADNativeAd) -> Void,
              onError: @escaping (String) -> Void) {
        guard AdService.shared.isReady else {
            // SDK noch nicht bootstrap'd → 0,5 s warten und erneut versuchen
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                Task { @MainActor in
                    self.load(onLoad: onLoad, onError: onError)
                }
            }
            return
        }
        self.onLoad = onLoad
        self.onError = onError
        let root = AdService.shared.topViewController()
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
        print("[Ads] Requesting native ad — adUnitID=\(AdService.shared.nativeAdUnitID)")
    }

    func adLoader(_ adLoader: GADAdLoader, didReceive nativeAd: GADNativeAd) {
        onLoad?(nativeAd)
    }

    func adLoader(_ adLoader: GADAdLoader, didFailToReceiveAdWithError error: Error) {
        onError?(error.localizedDescription)
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
        view.clipsToBounds = true

        // --- Subviews ---

        let badge = UILabel()
        badge.text = "Gesponsert"
        badge.font = .systemFont(ofSize: 9, weight: .semibold)
        badge.textColor = .secondaryLabel
        badge.translatesAutoresizingMaskIntoConstraints = false

        let icon = UIImageView()
        icon.contentMode = .scaleAspectFit
        icon.layer.cornerRadius = 6
        icon.layer.masksToBounds = true
        icon.translatesAutoresizingMaskIntoConstraints = false

        let headline = UILabel()
        headline.font = .systemFont(ofSize: 14, weight: .semibold)
        headline.textColor = .label
        headline.numberOfLines = 1
        headline.lineBreakMode = .byTruncatingTail
        headline.translatesAutoresizingMaskIntoConstraints = false

        let body = UILabel()
        body.font = .systemFont(ofSize: 11, weight: .regular)
        body.textColor = .secondaryLabel
        body.numberOfLines = 1
        body.lineBreakMode = .byTruncatingTail
        body.translatesAutoresizingMaskIntoConstraints = false

        let cta = UILabel()
        cta.font = .systemFont(ofSize: 11, weight: .semibold)
        cta.textColor = .tintColor
        cta.numberOfLines = 1
        cta.lineBreakMode = .byTruncatingTail
        cta.translatesAutoresizingMaskIntoConstraints = false

        // AdChoices-Slot. Wenn wir den Slot nicht explizit setzen, platziert
        // AdMob das AdChoices-Icon automatisch — und das landet teilweise
        // ausserhalb der Ad-View-Boundary, was den Validator triggert.
        // KEIN GADMediaView — der müsste ≥120x120pt sein, was in unseren
        // kompakten 96pt-Tile nicht passt. Das Media-Asset wird stattdessen
        // einfach nicht angezeigt — bei einem reinen Banner-Tile ist das ok.
        let adChoices = GADAdChoicesView()
        adChoices.translatesAutoresizingMaskIntoConstraints = false
        adChoices.backgroundColor = .clear

        view.addSubview(badge)
        view.addSubview(icon)
        view.addSubview(headline)
        view.addSubview(body)
        view.addSubview(cta)
        view.addSubview(adChoices)

        // --- Constraints ---

        NSLayoutConstraint.activate([
            // Icon links, vertikal zentriert
            icon.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            icon.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 40),
            icon.heightAnchor.constraint(equalToConstant: 40),
            icon.topAnchor.constraint(greaterThanOrEqualTo: view.topAnchor, constant: 4),
            icon.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -4),

            // AdChoices oben rechts, fest verankert innerhalb der Boundary
            adChoices.topAnchor.constraint(equalTo: view.topAnchor, constant: 2),
            adChoices.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -2),
            adChoices.widthAnchor.constraint(equalToConstant: 18),
            adChoices.heightAnchor.constraint(equalToConstant: 18),

            // Badge oben links neben dem Icon
            badge.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            badge.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            badge.trailingAnchor.constraint(lessThanOrEqualTo: adChoices.leadingAnchor, constant: -4),

            // Headline unter dem Badge — feste trailing-Anker für klare Boundary
            headline.topAnchor.constraint(equalTo: badge.bottomAnchor, constant: 3),
            headline.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            headline.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),

            // Body unter Headline
            body.topAnchor.constraint(equalTo: headline.bottomAnchor, constant: 2),
            body.leadingAnchor.constraint(equalTo: headline.leadingAnchor),
            body.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),

            // CTA fest unten verankert — kann nicht mehr überlaufen
            cta.topAnchor.constraint(greaterThanOrEqualTo: body.bottomAnchor, constant: 4),
            cta.leadingAnchor.constraint(equalTo: headline.leadingAnchor),
            cta.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            cta.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8)
        ])

        // --- AdMob-Verdrahtung ---
        view.iconView = icon
        view.headlineView = headline
        view.bodyView = body
        view.callToActionView = cta
        view.adChoicesView = adChoices

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
