import SwiftUI
import WidgetKit

@main
struct SimpleTrackingWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TrackingStatusWidget()
        WorkoutLiveActivityWidget()
    }
}
