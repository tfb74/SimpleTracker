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
    /// True wenn das Workout pausiert ist. GPS-Updates kommen weiter rein,
    /// werden aber NICHT zur Route oder Distanz hinzugefügt — bei Resume
    /// wird die letzte Position als Referenz für die nächste Distanz-
    /// Berechnung genutzt, sodass die Pause-Lücke nicht als Sprung gezählt
    /// wird.
    var isPaused = false
    private var previousMilestoneMeters: Double = 0
    private var previousAltitudeMeters: Double? = nil

    override init() {
        super.init()
        manager.delegate               = self
        manager.desiredAccuracy        = kCLLocationAccuracyBest
        manager.distanceFilter         = 5
        // WICHTIG: allowsBackgroundLocationUpdates wird NUR während eines
        // aktiven Workouts gesetzt — sonst zeigt iOS dauerhaft die
        // Location-Pille im Lock Screen und der Tracker läuft scheinbar weiter.
        manager.allowsBackgroundLocationUpdates = false
        manager.pausesLocationUpdatesAutomatically = false
        // showsBackgroundLocationIndicator: explizit aus solange nicht getrackt wird.
        manager.showsBackgroundLocationIndicator = false
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
        // Erst JETZT Background-Updates erlauben — beim Stop nehmen wir's zurück.
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.startUpdatingLocation()
    }

    /// Pausiert das Tracking: GPS-Empfang läuft weiter (sonst würde der
    /// erste Punkt nach Resume eine riesige Distanz-Lücke schaffen), aber
    /// neue Punkte werden NICHT zur Route hinzugefügt und nicht zur Distanz
    /// addiert. Live-Speed wird auf 0 gesetzt.
    func pauseTracking() {
        isPaused = true
        currentSpeedMPS = 0
    }

    /// Setzt das Tracking nach Pause fort. Die nächste empfangene Location
    /// wird als neuer Referenzpunkt für Distanz-Berechnung genutzt — das
    /// macht der `previousAltitudeMeters/recordedRoute.last`-Check in
    /// didUpdateLocations automatisch.
    func resumeTracking() {
        isPaused = false
    }

    func stopTracking() -> [RoutePoint] {
        isTracking = false
        isPaused = false
        manager.stopUpdatingLocation()
        // KRITISCH: Background-Berechtigung zurücknehmen, sonst behält iOS
        // die Location-Pille im Lock Screen aktiv, der GPS-Chip läuft weiter
        // und der Akku verbraucht sich.
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
        // Live-Werte clearen, damit eine evtl. stale Anzeige nicht mehr
        // suggeriert es würde noch was getrackt.
        currentSpeedMPS = 0
        return recordedRoute
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Nur Updates verarbeiten wenn aktiv getrackt wird — sonst ist eventuelle
        // stale Lieferung vom System irrelevant und sollte keine Live-Werte
        // mehr beeinflussen.
        guard isTracking else { return }
        guard let location = locations.last, location.horizontalAccuracy > 0 else { return }

        // Bei PAUSE: nur currentLocation aktualisieren (damit Resume mit
        // aktuellem Referenzpunkt startet), aber Speed=0 und KEINE Route-/
        // Distanz-/Höhen-Updates. Sonst wäre die Pause unsichtbar in den Daten.
        currentLocation = location
        if isPaused {
            currentSpeedMPS = 0
            return
        }

        currentSpeedMPS        = max(0, location.speed)
        currentAltitudeMeters  = location.altitude

        guard location.horizontalAccuracy < 20 else { return }

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
