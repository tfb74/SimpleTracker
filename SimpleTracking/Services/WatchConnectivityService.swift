import Foundation
import WatchConnectivity

@Observable
final class WatchConnectivityService: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityService()

    var isReachable                = false
    var liveMetrics                = WorkoutMetrics()
    var isWorkoutActiveOnWatch     = false

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func sendCommand(_ command: WatchCommand, workoutType: WorkoutType? = nil) {
        guard WCSession.default.isReachable else { return }
        var msg: [String: Any] = [WatchMessage.commandKey: command.rawValue]
        if let t = workoutType { msg[WatchMessage.workoutTypeKey] = t.rawValue }
        WCSession.default.sendMessage(msg, replyHandler: nil)
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { self.isReachable = session.isReachable }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { self.isReachable = session.isReachable }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let data    = message[WatchMessage.metricsKey] as? Data,
              let metrics = try? JSONDecoder().decode(WorkoutMetrics.self, from: data) else { return }
        DispatchQueue.main.async {
            self.liveMetrics              = metrics
            self.isWorkoutActiveOnWatch   = metrics.isActive
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession)     { WCSession.default.activate() }
}
