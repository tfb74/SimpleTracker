import Foundation
import HealthKit
import WatchConnectivity
import UserNotifications
import WatchKit

@Observable
final class WatchWorkoutService: NSObject {
    static let shared = WatchWorkoutService()

    private let store           = HKHealthStore()
    private var session:        HKWorkoutSession?
    private var builder:        HKLiveWorkoutBuilder?
    private var wcSession:      WCSession?
    private var metricTimer:    Timer?

    var isActive               = false
    var isPaused               = false
    var currentMetrics         = WorkoutMetrics()
    var currentWorkoutType:    WorkoutType = .running
    var elapsedSeconds:        TimeInterval = 0

    // milestone tracking
    private var previousMilestoneMeters: Double = 0
    private var unitPreference: UnitPreference = {
        let raw = UserDefaults.standard.string(forKey: "unitPreference") ?? ""
        return UnitPreference(rawValue: raw) ?? .metric
    }()

    private override init() {
        super.init()
        setupWatchConnectivity()
        requestNotificationPermission()
    }

    // MARK: - Authorization

    func requestAuthorization() async throws {
        let share: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
        ]
        let read: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
        ]
        try await store.requestAuthorization(toShare: share, read: read)
    }

    // MARK: - Workout Control

    func startWorkout(type: WorkoutType) async throws {
        currentWorkoutType           = type
        currentMetrics               = WorkoutMetrics()
        currentMetrics.workoutType   = type.rawValue
        currentMetrics.isActive      = true
        previousMilestoneMeters      = 0
        elapsedSeconds               = 0

        let config                   = HKWorkoutConfiguration()
        config.activityType          = type.hkWorkoutActivityType
        config.locationType          = .outdoor

        session = try HKWorkoutSession(healthStore: store, configuration: config)
        builder = session?.associatedWorkoutBuilder()
        builder?.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
        session?.delegate  = self
        builder?.delegate  = self

        session?.startActivity(with: Date())
        try await builder?.beginCollection(at: Date())

        isActive = true
        startTimer()
    }

    func stopWorkout() async throws {
        stopTimer()
        session?.end()
        try await builder?.endCollection(at: Date())
        _ = try await builder?.finishWorkout()

        isActive             = false
        isPaused             = false
        currentMetrics.isActive = false
        elapsedSeconds       = 0
        currentMetrics       = WorkoutMetrics()
        sendMetrics()
    }

    func pauseWorkout()  { session?.pause();  isPaused = true;  stopTimer() }
    func resumeWorkout() { session?.resume(); isPaused = false; startTimer() }

    // MARK: - Timer

    private func startTimer() {
        metricTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.elapsedSeconds             += 1
            self.currentMetrics.durationSeconds = self.elapsedSeconds
            self.checkMilestone()
            self.sendMetrics()
        }
    }

    private func stopTimer() { metricTimer?.invalidate(); metricTimer = nil }

    // MARK: - Milestone Notifications

    private func checkMilestone() {
        let current  = currentMetrics.distanceMeters
        let interval = unitPreference.notificationIntervalMeters
        let prevN    = Int(previousMilestoneMeters / interval)
        let currN    = Int(current / interval)
        guard currN > prevN, currN > 0 else { return }

        previousMilestoneMeters = current

        // Haptic feedback
        WKInterfaceDevice.current().play(.notification)

        // Local notification on Watch
        let label    = unitPreference.distanceLabel
        let content  = UNMutableNotificationContent()
        content.title = lf("%d %@ 🎉", currN, label)
        content.body  = paceLabel()
        content.sound = .default
        let req = UNNotificationRequest(identifier: "milestone_\(currN)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    private func paceLabel() -> String {
        guard currentMetrics.currentSpeedMPS > 0 else { return "" }
        switch unitPreference {
        case .metric:
            let s = 1_000 / currentMetrics.currentSpeedMPS
            return lf("Tempo: %d:%02d min/km", Int(s) / 60, Int(s) % 60)
        case .imperial:
            let s = 1_609.344 / currentMetrics.currentSpeedMPS
            return lf("Pace: %d:%02d min/mi", Int(s) / 60, Int(s) % 60)
        }
    }

    // MARK: - WatchConnectivity

    private func setupWatchConnectivity() {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        s.delegate = self
        s.activate()
        wcSession = s
    }

    func sendMetrics() {
        guard WCSession.default.isReachable,
              let data = try? JSONEncoder().encode(currentMetrics) else { return }
        WCSession.default.sendMessage([WatchMessage.metricsKey: data], replyHandler: nil, errorHandler: nil)
    }

    // MARK: - Notifications permission

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WatchWorkoutService: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState, date: Date) {}
    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WatchWorkoutService: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        for type in collectedTypes {
            guard let qt = type as? HKQuantityType else { continue }
            let stats = workoutBuilder.statistics(for: qt)

            switch qt.identifier {
            case HKQuantityTypeIdentifier.heartRate.rawValue:
                currentMetrics.heartRate = stats?.mostRecentQuantity()?.doubleValue(for: HKUnit(from: "count/min")) ?? 0
            case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue:
                currentMetrics.activeCalories = stats?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
            case HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue:
                let d = stats?.sumQuantity()?.doubleValue(for: .meter()) ?? 0
                currentMetrics.distanceMeters = d
                if elapsedSeconds > 0 { currentMetrics.currentSpeedMPS = d / elapsedSeconds }
            case HKQuantityTypeIdentifier.stepCount.rawValue:
                currentMetrics.steps = Int(stats?.sumQuantity()?.doubleValue(for: .count()) ?? 0)
            default: break
            }
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchWorkoutService: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let cmdStr = message[WatchMessage.commandKey] as? String,
              let cmd    = WatchCommand(rawValue: cmdStr) else { return }
        Task {
            switch cmd {
            case .startWorkout:
                let typeRaw = message[WatchMessage.workoutTypeKey] as? String ?? WorkoutType.walking.rawValue
                let type    = WorkoutType(rawValue: typeRaw) ?? .walking
                try? await startWorkout(type: type)
            case .stopWorkout:    try? await stopWorkout()
            case .pauseWorkout:   pauseWorkout()
            case .resumeWorkout:  resumeWorkout()
            }
        }
    }
}
