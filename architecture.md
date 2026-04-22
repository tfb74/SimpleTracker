# Architecture — SimpleTracking

## Projekt-Struktur

```
SimpleTracking/
├── project.yml                          # XcodeGen-Config (regeneriert .xcodeproj)
├── SimpleTracking.xcodeproj/            # Generiert — nicht manuell bearbeiten
│
├── Shared/                              # Code für iOS + watchOS
│   ├── WorkoutType.swift                # Enum: running, walking, cycling, hiking
│   ├── WatchMessage.swift               # WorkoutMetrics, WatchCommand, WatchMessage-Keys
│   └── UserSettings.swift              # UnitPreference, AppColorScheme, UserSettings (@Observable)
│
├── SimpleTracking/                      # iOS App
│   ├── App/
│   │   └── SimpleTrackingApp.swift      # @main, Environment-Setup, preferredColorScheme
│   ├── Models/
│   │   ├── RoutePoint.swift             # GPS-Punkt (CLLocation wrapper)
│   │   └── WorkoutRecord.swift          # Vollständiger Workout (inkl. Route)
│   ├── Services/
│   │   ├── HealthKitService.swift       # HKHealthStore: read/write/import
│   │   ├── LocationService.swift        # CLLocationManager, Routenaufzeichnung, Distanzmessung
│   │   ├── NotificationService.swift    # UNUserNotificationCenter, km/mi-Milestone-Logik
│   │   └── WatchConnectivityService.swift # WCSession iOS-Seite
│   └── Views/
│       ├── ContentView.swift            # TabView (Heute, Workout, Verlauf, Statistiken, Einstellungen)
│       ├── Dashboard/DashboardView.swift
│       ├── Workout/ActiveWorkoutView.swift  # Live-Tracking + Karte + Milestone-Trigger
│       ├── Map/RouteMapView.swift           # RouteMapView (live) + StaticRouteMapView (History)
│       ├── Statistics/StatisticsView.swift  # CatmullRom-Liniendiagramme, Tag/Woche/Monat
│       ├── Import/ImportView.swift
│       ├── History/
│       │   ├── WorkoutHistoryView.swift
│       │   └── WorkoutDetailView.swift
│       └── Settings/SettingsView.swift      # Dark/Light/System, km/mi
│
└── SimpleTrackingWatch/                 # watchOS App
    ├── App/SimpleTrackingWatchApp.swift
    ├── Services/WatchWorkoutService.swift   # HKWorkoutSession, HKLiveWorkoutBuilder, WCSession
    └── Views/
        ├── WatchMainView.swift              # Workout-Typ-Auswahl
        └── WatchActiveWorkoutView.swift     # Live-Metriken + Pause/Stop + Haptic-Milestone
```

## Datenfluss

```
Apple Watch
  └─ HKLiveWorkoutBuilder → WatchWorkoutService
        └─ WCSession.sendMessage() ──────────────→ WatchConnectivityService (iOS)
                                                          └─ liveMetrics → ActiveWorkoutView

GPS (iPhone)
  └─ CLLocationManager → LocationService
        └─ recordedRoute, totalDistanceMeters → ActiveWorkoutView
              └─ NotificationService.checkMilestone() → UNUserNotificationCenter

Workout-Ende (iPhone)
  └─ HealthKitService.saveWorkout() → HKHealthStore → Apple Health

Import
  └─ HealthKitService.loadWorkouts() → HKSampleQuery → [WorkoutRecord] → WorkoutHistoryView
```

## Plattform-Targets

| Target               | Min. OS   | Frameworks                              |
|----------------------|-----------|-----------------------------------------|
| SimpleTracking (iOS) | iOS 17.0  | SwiftUI, HealthKit, CoreLocation, MapKit, Swift Charts, WatchConnectivity, UserNotifications |
| SimpleTrackingWatch  | watchOS 10.0 | SwiftUI, HealthKit, WatchKit, WatchConnectivity, UserNotifications |

## Einheitensystem
- Intern: immer Meter / Meter pro Sekunde
- UI: via `UnitPreference.formatted(meters:)` in km oder miles
- Milestone-Schwelle: `UnitPreference.notificationIntervalMeters` (1000 m oder 1609.344 m)

## State-Management
- `@Observable` + `.environment()` — kein `ObservableObject`
- `UserSettings` persistiert in `UserDefaults`
- Source of Truth für Workout-Daten: Apple Health (HKHealthStore)
