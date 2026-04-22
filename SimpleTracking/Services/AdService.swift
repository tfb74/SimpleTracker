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
            _ = await GADMobileAds.sharedInstance().start()
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
            try? await Task.sleep(for: .milliseconds(350))
            presentWeeklyInterstitial()
        }
    }

    func forceDebugWeeklyInterstitialPrompt() {
        preloadInterstitialIfNeeded()
        weeklyInterstitialPrompt = WeeklyInterstitialPrompt(skipsRemaining: weeklyInterstitialSkipsRemaining)
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
            preloadInterstitialIfNeeded()
            return
        }

        guard let rootViewController = topViewController() else { return }

        do {
            try interstitialAd.canPresent(fromRootViewController: rootViewController)
            interstitialAd.present(fromRootViewController: rootViewController)
        } catch {
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

        do {
            try await UMPConsentForm.loadAndPresentIfRequired(from: nil)
        } catch {
            print("[Ads] UMP form present failed: \(error.localizedDescription)")
        }
    }
    #endif

    private func requestATTIfNeeded() async {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
        _ = await ATTrackingManager.requestTrackingAuthorization()
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

    #if canImport(GoogleMobileAds)
    private func topViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController?
            .topMostPresentedViewController
    }
    #endif
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

private extension UIViewController {
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
#endif
