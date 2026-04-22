import SwiftUI
import MapKit

// MARK: - Live map during workout

struct RouteMapView: View {
    let routePoints: [RoutePoint]
    let currentLocation: CLLocation?

    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Map(position: $position) {
            if let loc = currentLocation {
                Annotation("", coordinate: loc.coordinate) {
                    ZStack {
                        Circle().fill(.blue.opacity(0.2)).frame(width: 32, height: 32)
                        Circle().fill(.blue).frame(width: 14, height: 14)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
            }
            let liveRoute = simplifiedLiveRoutePoints(routePoints)
            if liveRoute.count >= 2 {
                MapPolyline(coordinates: liveRoute.map(\.coordinate))
                    .stroke(.blue, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .onChange(of: routePoints.count) { _, newCount in
            guard scenePhase == .active, let last = routePoints.last else { return }
            guard newCount < 20 || newCount.isMultiple(of: 8) else { return }
            position = .camera(MapCamera(centerCoordinate: last.coordinate, distance: 500))
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, let last = routePoints.last else { return }
            position = .camera(MapCamera(centerCoordinate: last.coordinate, distance: 500))
        }
    }

    /// Keep live workout rendering cheap enough to survive foregrounding after
    /// longer background tracking sessions.
    private func simplifiedLiveRoutePoints(_ points: [RoutePoint], maxPoints: Int = 300) -> [RoutePoint] {
        guard points.count > maxPoints else { return points }

        let step = max(1, points.count / maxPoints)
        var simplified: [RoutePoint] = []
        simplified.reserveCapacity(maxPoints + 1)

        for index in stride(from: 0, to: points.count, by: step) {
            simplified.append(points[index])
        }

        if let last = points.last, simplified.last?.id != last.id {
            simplified.append(last)
        }

        return simplified
    }
}

// MARK: - Static map for workout history

/// Interactive (pan / pinch-zoom / rotate) but no user-tracking — used in
/// the workout detail screen. NOT `.disabled` so gestures work.
struct StaticRouteMapView: View {
    let routePoints: [RoutePoint]

    @State private var position: MapCameraPosition

    init(routePoints: [RoutePoint]) {
        self.routePoints = routePoints
        _position = State(initialValue: Self.initialPosition(for: routePoints))
    }

    private static func initialPosition(for pts: [RoutePoint]) -> MapCameraPosition {
        guard pts.count >= 2 else { return .automatic }
        let lats = pts.map(\.latitude)
        let lons = pts.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude:  (lats.max()! + lats.min()!) / 2,
            longitude: (lons.max()! - lons.min()!) / 2 + lons.min()!
        )
        let span = MKCoordinateSpan(
            latitudeDelta:  max(0.002, (lats.max()! - lats.min()!) * 1.4),
            longitudeDelta: max(0.002, (lons.max()! - lons.min()!) * 1.4)
        )
        return .region(MKCoordinateRegion(center: center, span: span))
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Map(position: $position, interactionModes: [.pan, .zoom, .rotate]) {
                // Route polyline, colored by speed segment.
                ForEach(speedSegments(routePoints)) { seg in
                    MapPolyline(coordinates: seg.coords)
                        .stroke(seg.color, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
                if let first = routePoints.first {
                    Annotation("Start", coordinate: first.coordinate) {
                        Circle().fill(.green).frame(width: 14, height: 14)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
                if let last = routePoints.last, routePoints.count > 1 {
                    Annotation("Ziel", coordinate: last.coordinate) {
                        Circle().fill(.red).frame(width: 14, height: 14)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
            }
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))

            if routePoints.count >= 2 {
                SpeedLegend(points: routePoints)
                    .padding(8)
            }
        }
    }
}

// MARK: - Speed-colored polyline helpers

struct SpeedSegment: Identifiable {
    let id = UUID()
    let coords: [CLLocationCoordinate2D]
    let color: Color
}

/// Split a route into short segments colored by local speed.
/// Uses a rolling window so short GPS glitches don't flash through the palette.
func speedSegments(_ points: [RoutePoint]) -> [SpeedSegment] {
    guard points.count >= 2 else { return [] }
    let speeds = points.map { max(0, $0.speed) }

    // Percentile-based color scale — robust against a few outlier spikes.
    let sorted = speeds.sorted()
    let p10 = sorted[Int(Double(sorted.count - 1) * 0.10)]
    let p50 = sorted[Int(Double(sorted.count - 1) * 0.50)]
    let p90 = sorted[Int(Double(sorted.count - 1) * 0.90)]
    // If nearly everything has zero speed (imported without GPS speed),
    // fall back to one blue segment so we don't draw pure red.
    let hasSpeed = p90 > 0.2

    func color(for speed: Double) -> Color {
        guard hasSpeed else { return .blue }
        if speed < p10 { return Color(red: 0.35, green: 0.70, blue: 1.00) }    // very slow — light blue
        if speed < p50 { return Color(red: 0.20, green: 0.85, blue: 0.35) }    // slow — green
        if speed < p90 { return Color(red: 1.00, green: 0.75, blue: 0.10) }    // medium — yellow/orange
        return           Color(red: 0.95, green: 0.25, blue: 0.20)             // fast — red
    }

    // Group consecutive points sharing the same color.
    var segments: [SpeedSegment] = []
    var currentColor = color(for: speeds[0])
    var currentCoords: [CLLocationCoordinate2D] = [points[0].coordinate]

    for i in 1..<points.count {
        let c = color(for: speeds[i])
        currentCoords.append(points[i].coordinate)
        if c != currentColor {
            segments.append(SpeedSegment(coords: currentCoords, color: currentColor))
            currentColor = c
            currentCoords = [points[i].coordinate]
        }
    }
    if !currentCoords.isEmpty {
        segments.append(SpeedSegment(coords: currentCoords, color: currentColor))
    }
    return segments
}

// MARK: - Speed legend

struct SpeedLegend: View {
    let points: [RoutePoint]

    var body: some View {
        let speeds = points.map { max(0, $0.speed) }
        let sorted = speeds.sorted()
        guard let maxS = sorted.last, maxS > 0.2 else { return AnyView(EmptyView()) }
        let p10 = sorted[Int(Double(sorted.count - 1) * 0.10)]
        let p50 = sorted[Int(Double(sorted.count - 1) * 0.50)]
        let p90 = sorted[Int(Double(sorted.count - 1) * 0.90)]

        return AnyView(
            HStack(spacing: 6) {
                legendDot(color: Color(red: 0.35, green: 0.70, blue: 1.00), text: "<\(kmh(p10))")
                legendDot(color: Color(red: 0.20, green: 0.85, blue: 0.35), text: "\(kmh(p10))–\(kmh(p50))")
                legendDot(color: Color(red: 1.00, green: 0.75, blue: 0.10), text: "\(kmh(p50))–\(kmh(p90))")
                legendDot(color: Color(red: 0.95, green: 0.25, blue: 0.20), text: ">\(kmh(p90))")
            }
            .font(.caption2.weight(.medium))
            .padding(.vertical, 6).padding(.horizontal, 10)
            .background(.ultraThinMaterial, in: Capsule())
        )
    }

    private func kmh(_ mps: Double) -> String { String(format: "%.0f", mps * 3.6) }

    private func legendDot(color: Color, text: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
        }
    }
}
