import Foundation
import CoreLocation

struct RoutePoint: Codable, Identifiable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let speed: Double      // m/s, already clamped to >= 0
    let timestamp: Date

    init(location: CLLocation) {
        id        = UUID()
        latitude  = location.coordinate.latitude
        longitude = location.coordinate.longitude
        altitude  = location.altitude
        speed     = max(0, location.speed)
        timestamp = location.timestamp
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var clLocation: CLLocation {
        CLLocation(
            coordinate: coordinate,
            altitude: altitude,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: 0,
            speed: speed,
            timestamp: timestamp
        )
    }
}
