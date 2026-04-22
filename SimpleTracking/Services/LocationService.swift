import Foundation
import CoreLocation

@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    private let manager = CLLocationManager()

    var currentLocation: CLLocation?
    var currentSpeedMPS: Double = 0
    var currentAltitudeMeters: Double = 0
    var totalElevationGainMeters: Double = 0
    var recordedRoute: [RoutePoint] = []
    var isTracking = false
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var accuracyAuthorization: CLAccuracyAuthorization = .reducedAccuracy

    // milestone tracking
    var totalDistanceMeters: Double = 0
    private var previousMilestoneMeters: Double = 0
    private var previousAltitudeMeters: Double? = nil

    override init() {
        super.init()
        manager.delegate               = self
        manager.desiredAccuracy        = kCLLocationAccuracyBest
        manager.distanceFilter         = 5
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = false
        authorizationStatus = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization
    }

    func requestAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    func startTracking(route: [RoutePoint] = [], totalDistanceMeters: Double = 0) {
        recordedRoute                = route
        self.totalDistanceMeters     = totalDistanceMeters
        previousMilestoneMeters      = 0
        previousAltitudeMeters       = route.last?.altitude
        currentLocation              = route.last?.clLocation
        currentSpeedMPS              = route.last?.speed ?? 0
        currentAltitudeMeters        = route.last?.altitude ?? 0
        totalElevationGainMeters     = 0
        isTracking                   = true
        manager.startUpdatingLocation()
    }

    func stopTracking() -> [RoutePoint] {
        isTracking = false
        manager.stopUpdatingLocation()
        return recordedRoute
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy > 0 else { return }
        currentLocation        = location
        currentSpeedMPS        = max(0, location.speed)
        currentAltitudeMeters  = location.altitude

        guard isTracking, location.horizontalAccuracy < 20 else { return }

        if let last = recordedRoute.last {
            let prev = CLLocation(latitude: last.latitude, longitude: last.longitude)
            let delta = location.distance(from: prev)
            totalDistanceMeters += delta
        }

        if location.verticalAccuracy > 0 {
            if let prev = previousAltitudeMeters {
                let gain = location.altitude - prev
                if gain > 0 { totalElevationGainMeters += gain }
            }
            previousAltitudeMeters = location.altitude
        }

        recordedRoute.append(RoutePoint(location: location))
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization
    }
}
