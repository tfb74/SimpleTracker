import Foundation
import SwiftUI
import AppTrackingTransparency
import UIKit

#if canImport(GoogleMobileAds)
import GoogleMobileAds
import UserMessagingPlatform
#endif

@MainActor
@Observable
final class AdService: NSObject {
    static let shared = AdService()

    static let weeklyInterstitialSkipLimit = 3

    static let testNativeAdUnitID = "ca-app-pub-3940256099942544/3986624511"
    static let testInterstitialAdUnitID = "ca-app-pub-3940256099942544/4411468910"

    static let productionNativeAdUnitID = "ca-app-pub-9685354539860584/5525660581"
    static let productionInterstitialAdUnitID = "ca-app-pub-9685354539860584/9863526692"

    struct WeeklyInterstitialPrompt: Identifiable, Equatable {
        let id = UUID()
        let skipsRemaining: Int

        var canSkip: Bool { skipsRemaining > 0 }
    }

    enum InterstitialLoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
        case unavailable
    }

    #if DEBUG
    var nativeAdUnitID: String = AdService.testNativeAdUnitID
    var interstitialAdUnitID: String = AdService.testInterstitialAdUnitID
    #else
    var nativeAdUnitID: String = AdService.productionNativeAdUnitID
    var interstitialAdUnitID: String = AdService.productionInterstitialAdUnitID
    #endif

    private(set) var isReady = false
    private(set) var interstitialLoadState: InterstitialLoadState = .idle
    private(set) var lastWeeklyInterstitialShownAt: Date?
    private(set) var weeklyInterstitialSkipCount = 0

    // Debug-Diagnose: für DEBUG-Anzeige im UI
    private(set) var diag_umpStatus: String = "—"
    private(set) var diag_attStatus: String = "—"
    private(set) var diag_sdkStarted: Bool = false
    private(set) var diag_lastNativeAdError: String?
    private(set) var diag_lastNativeAdLoadedAt: Date?

    var weeklyInterstitialPrompt: WeeklyInterstitialPrompt?
    var debugInterstitialPreviewPresented = false

    private var hasStarted = false

    #if canImport(GoogleMobileAds)
    private var interstitialAd: GADInterstitialAd?
    #endif

    private static let lastShownKey = "ads.weeklyInterstitial.lastShownAt"
    private static let skipCountKey = "ads.weeklyInterstitial.skipCount"
    private static let skipWeekKey = "ads.weeklyInterstitial.skipWeek"

    private override init() {
        super.init()
        refreshPersistentState()
    }

    var weeklyInterstitialSkipsRemaining: Int {
        max(0, Self.weeklyInterstitialSkipLimit - weeklyInterstitialSkipCount)
    }

    var hasShownWeeklyInterstitialThisWeek: Bool {
        guard let lastWeeklyInterstitialShownAt else { return false }
        return Self.weekID(for: lastWeeklyInterstitialShownAt) == Self.currentWeekID
    }

    var interstitialStatusLabel: String {
        #if DEBUG && targetEnvironment(simulator)
        if interstitialLoadState == .loaded {
            return lt("Geladen")
        }
        return lt("Simulator-Vorschau bereit")
        #else
        switch interstitialLoadState {
        case .idle:
            return lt("Noch nicht geladen")
        case .loading:
            return lt("Lädt")
        case .loaded:
            return lt("Geladen")
        case .failed:
            return lt("Kein Fill")
        case .unavailable:
            return lt("Nicht verfügbar")
        }
        #endif
    }

    var lastWeeklyInterstitialShownLabel: String {
        guard let lastWeeklyInterstitialShownAt else { return lt("Noch nie") }
        return lastWeeklyInterstitialShownAt.formatted(date: .abbreviated, time: .shortened)
    }

    var weeklyInterstitialSummary: String {
        if hasShownWeeklyInterstitialThisWeek {
            return lt("Diese Woche bereits gezeigt")
        }
        if weeklyInterstitialSkipsRemaining > 0 {
            return lf("Fällig, %d x überspringbar", weeklyInterstitialSkipsRemaining)
        }
        return lt("Fällig, nächstes Mal ohne Skip")
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        refreshPersistentState()

        #if canImport(GoogleMobileAds)
        Task {
            await requestConsentIfNeeded()
            await requestATTIfNeeded()

            // Test-Device automatisch registrieren in DEBUG, damit auf dem
            // realen iPhone garantiert Test-Ads kommen.
            #if DEBUG
            // GADSimulatorID ist nur für den Simulator — auf einem echten
            // iPhone genügen die TEST-Ad-Unit-IDs (ca-app-pub-3940256099942544/...).
            // Diese liefern auf JEDEM Gerät immer Test-Ads.
            GADMobileAds.sharedInstance().requestConfiguration.testDeviceIdentifiers = []
            print("[Ads] DEBUG mode — using TEST ad unit IDs")
            print("[Ads] App ID from Info.plist: \(Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") ?? "missing!")")
            print("[Ads] Native ad unit ID: \(nativeAdUnitID)")
            print("[Ads] Interstitial ad unit ID: \(interstitialAdUnitID)")
            #endif

            _ = await GADMobileAds.sharedInstance().start()
            diag_sdkStarted = true
            print("[Ads] GoogleMobileAds SDK started. Adapter status:")
            for (name, status) in GADMobileAds.sharedInstance().initializationStatus.adapterStatusesByClassName {
                print("[Ads]   • \(name): \(status.state.rawValue) — \(status.description)")
            }
            isReady = true
            preloadInterstitialIfNeeded()
        }
        #else
        isReady = false
        interstitialLoadState = .unavailable
        #endif
    }

    func considerWeeklyInterstitialOffer() {
        refreshPersistentState()
        preloadInterstitialIfNeeded()

        guard !hasShownWeeklyInterstitialThisWeek else { return }
        guard weeklyInterstitialPrompt == nil else { return }
        guard hasInterstitialAvailableForPrompt else { return }

        weeklyInterstitialPrompt = WeeklyInterstitialPrompt(skipsRemaining: weeklyInterstitialSkipsRemaining)
    }

    func skipWeeklyInterstitialPrompt() {
        refreshPersistentState()
        guard weeklyInterstitialSkipsRemaining > 0 else {
            weeklyInterstitialPrompt = nil
            return
        }

        weeklyInterstitialSkipCount += 1
        persistSkipState()
        weeklyInterstitialPrompt = nil
    }

    func confirmWeeklyInterstitialPrompt() {
        weeklyInterstitialPrompt = nil

        Task {
            // Sheet braucht Zeit zum dismissen — sonst kann der nächste Modal
            // nicht präsentiert werden (Top-VC ist noch das Sheet das gerade verschwindet).
            try? await Task.sleep(for: .milliseconds(700))
            presentWeeklyInterstitial()
        }
    }

    func forceDebugWeeklyInterstitialPrompt() {
        preloadInterstitialIfNeeded()
        weeklyInterstitialPrompt = WeeklyInterstitialPrompt(skipsRemaining: weeklyInterstitialSkipsRemaining)
    }

    /// Direktes Testen: Vollbild-Ad SOFORT zeigen ohne Prompt-Sheet.
    /// Wartet bis zu 10 Sekunden auf die Ad falls noch nicht geladen.
    /// Nur als Debug-Hilfe gedacht.
    func showInterstitialNow() {
        print("[Ads] showInterstitialNow: load-state=\(interstitialLoadState), hasAd=\(interstitialAd != nil)")
        Task { @MainActor in
            // Trigger preload falls noch nicht passiert
            preloadInterstitialIfNeeded()

            // Warte bis zu 10s auf Load
            for attempt in 0..<20 {
                if interstitialAd != nil {
                    print("[Ads] showInterstitialNow: ad ready after \(attempt * 500)ms")
                    presentWeeklyInterstitial()
                    return
                }
                if case .failed(let msg) = interstitialLoadState {
                    print("[Ads] showInterstitialNow: aborted, load failed: \(msg)")
                    return
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
            print("[Ads] showInterstitialNow: TIMEOUT after 10s, state=\(interstitialLoadState)")
        }
    }

    func resetWeeklyInterstitialState() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.lastShownKey)
        defaults.removeObject(forKey: Self.skipCountKey)
        defaults.removeObject(forKey: Self.skipWeekKey)

        lastWeeklyInterstitialShownAt = nil
        weeklyInterstitialSkipCount = 0
        weeklyInterstitialPrompt = nil
        debugInterstitialPreviewPresented = false
        #if canImport(GoogleMobileAds)
        interstitialAd = nil
        #endif
        interstitialLoadState = .idle
        preloadInterstitialIfNeeded()
    }

    func dismissDebugInterstitialPreview() {
        debugInterstitialPreviewPresented = false
    }

    private var hasInterstitialAvailableForPrompt: Bool {
        #if DEBUG && targetEnvironment(simulator)
        true
        #elseif canImport(GoogleMobileAds)
        interstitialAd != nil
        #else
        false
        #endif
    }

    private func presentWeeklyInterstitial() {
        #if DEBUG && targetEnvironment(simulator)
        if interstitialLoadState != .loaded {
            debugInterstitialPreviewPresented = true
            recordWeeklyInterstitialShown()
            return
        }
        #endif

        #if canImport(GoogleMobileAds)
        guard let interstitialAd else {
            print("[Ads] presentWeeklyInterstitial: no ad loaded, triggering preload (state=\(interstitialLoadState))")
            preloadInterstitialIfNeeded()
            return
        }

        guard let rootViewController = topViewController() else {
            print("[Ads] presentWeeklyInterstitial: NO topViewController found")
            return
        }
        print("[Ads] presentWeeklyInterstitial: presenting from \(type(of: rootViewController))")

        do {
            try interstitialAd.canPresent(fromRootViewController: rootViewController)
            interstitialAd.present(fromRootViewController: rootViewController)
            print("[Ads] presentWeeklyInterstitial: present() called successfully")
        } catch {
            print("[Ads] presentWeeklyInterstitial: canPresent failed: \(error.localizedDescription)")
            interstitialLoadState = .failed(error.localizedDescription)
            self.interstitialAd = nil
            preloadInterstitialIfNeeded()
        }
        #endif
    }

    private func refreshPersistentState() {
        let defaults = UserDefaults.standard
        lastWeeklyInterstitialShownAt = defaults.object(forKey: Self.lastShownKey) as? Date

        let currentWeek = Self.currentWeekID
        let storedWeek = defaults.string(forKey: Self.skipWeekKey)
        if storedWeek != currentWeek {
            weeklyInterstitialSkipCount = 0
            defaults.set(currentWeek, forKey: Self.skipWeekKey)
            defaults.set(0, forKey: Self.skipCountKey)
        } else {
            weeklyInterstitialSkipCount = defaults.integer(forKey: Self.skipCountKey)
        }
    }

    private func persistSkipState() {
        let defaults = UserDefaults.standard
        defaults.set(Self.currentWeekID, forKey: Self.skipWeekKey)
        defaults.set(weeklyInterstitialSkipCount, forKey: Self.skipCountKey)
    }

    private func recordWeeklyInterstitialShown() {
        let now = Date()
        lastWeeklyInterstitialShownAt = now
        UserDefaults.standard.set(now, forKey: Self.lastShownKey)
        weeklyInterstitialPrompt = nil
    }

    private static let isoCalendar: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        return calendar
    }()

    private static var currentWeekID: String {
        weekID(for: Date())
    }

    private static func weekID(for date: Date) -> String {
        let components = isoCalendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let year = components.yearForWeekOfYear ?? 0
        let week = components.weekOfYear ?? 0
        return "\(year)-W\(week)"
    }

    #if canImport(GoogleMobileAds)
    private func requestConsentIfNeeded() async {
        let parameters = UMPRequestParameters()
        parameters.tagForUnderAgeOfConsent = false

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            UMPConsentInformation.sharedInstance.requestConsentInfoUpdate(with: parameters) { error in
                if let error {
                    print("[Ads] UMP requestConsentInfoUpdate failed: \(error.localizedDescription)")
                }
                cont.resume()
            }
        }

        // Status loggen
        let info = UMPConsentInformation.sharedInstance
        let status = info.consentStatus
        let formStatus = info.formStatus
        diag_umpStatus = "consent=\(consentLabel(status)) form=\(formLabel(formStatus))"
        print("[Ads] UMP consent status: \(diag_umpStatus)")

        // Form präsentieren — mit explizitem Top-View-Controller, nicht nil.
        let topVC: UIViewController? = topViewController()
        do {
            try await UMPConsentForm.loadAndPresentIfRequired(from: topVC)
            print("[Ads] UMP form presented (or not required)")
        } catch {
            print("[Ads] UMP form present failed: \(error.localizedDescription)")
            diag_umpStatus += " · form-error"
        }
    }

    private func consentLabel(_ s: UMPConsentStatus) -> String {
        switch s {
        case .notRequired: return "notRequired"
        case .required: return "required"
        case .obtained: return "obtained"
        case .unknown: return "unknown"
        @unknown default: return "??"
        }
    }
    private func formLabel(_ s: UMPFormStatus) -> String {
        switch s {
        case .available: return "available"
        case .unavailable: return "unavailable"
        case .unknown: return "unknown"
        @unknown default: return "??"
        }
    }
    #endif

    private func requestATTIfNeeded() async {
        if ATTrackingManager.trackingAuthorizationStatus != .notDetermined {
            diag_attStatus = attLabel(ATTrackingManager.trackingAuthorizationStatus)
            return
        }
        let result = await ATTrackingManager.requestTrackingAuthorization()
        diag_attStatus = attLabel(result)
        print("[Ads] ATT result: \(diag_attStatus)")
    }

    private func attLabel(_ s: ATTrackingManager.AuthorizationStatus) -> String {
        switch s {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorized: return "authorized"
        @unknown default: return "??"
        }
    }

    /// Setzt den UMP-Consent komplett zurück — User muss beim nächsten
    /// App-Start neu zustimmen. Hilfreich zum Testen.
    func resetUMPConsent() {
        #if canImport(GoogleMobileAds)
        UMPConsentInformation.sharedInstance.reset()
        diag_umpStatus = "reset"
        print("[Ads] UMP consent reset")
        #endif
    }

    /// Notiert einen Native-Ad-Fehler/Erfolg fürs Debug-UI.
    func recordNativeAdResult(error: String?) {
        diag_lastNativeAdError = error
        if error == nil { diag_lastNativeAdLoadedAt = Date() }
    }

    func topViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController?
            .topMostPresentedViewController
    }

    func preloadInterstitialIfNeeded() {
        guard isReady else { return }

        #if canImport(GoogleMobileAds)
        guard interstitialAd == nil else {
            interstitialLoadState = .loaded
            return
        }
        guard interstitialLoadState != .loading else { return }

        interstitialLoadState = .loading

        GADInterstitialAd.load(withAdUnitID: interstitialAdUnitID, request: GADRequest()) { [weak self] ad, error in
            Task { @MainActor [weak self] in
                guard let self else { return }

                if let error {
                    self.interstitialLoadState = .failed(error.localizedDescription)
                    self.interstitialAd = nil
                    print("[Ads] Interstitial failed: \(error.localizedDescription)")
                    return
                }

                self.interstitialAd = ad
                self.interstitialAd?.fullScreenContentDelegate = self
                self.interstitialLoadState = ad == nil ? .failed("Leere Antwort") : .loaded
            }
        }
        #else
        interstitialLoadState = .unavailable
        #endif
    }

}

#if canImport(GoogleMobileAds)
@MainActor
extension AdService: @preconcurrency GADFullScreenContentDelegate {
    func adWillPresentFullScreenContent(_ ad: any GADFullScreenPresentingAd) {
        recordWeeklyInterstitialShown()
    }

    func ad(_ ad: any GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: any Error) {
        interstitialLoadState = .failed(error.localizedDescription)
        interstitialAd = nil
        print("[Ads] Interstitial present failed: \(error.localizedDescription)")
        preloadInterstitialIfNeeded()
    }

    func adDidDismissFullScreenContent(_ ad: any GADFullScreenPresentingAd) {
        interstitialAd = nil
        interstitialLoadState = .idle
        preloadInterstitialIfNeeded()
    }
}

#endif

extension UIViewController {
    var topMostPresentedViewController: UIViewController {
        if let presentedViewController {
            return presentedViewController.topMostPresentedViewController
        }
        if let navigationController = self as? UINavigationController {
            return navigationController.visibleViewController?.topMostPresentedViewController ?? navigationController
        }
        if let tabBarController = self as? UITabBarController {
            return tabBarController.selectedViewController?.topMostPresentedViewController ?? tabBarController
        }
        return self
    }
}
