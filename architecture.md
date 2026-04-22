# Architecture — SimpleTracking

## Projekt-Struktur

```
SimpleTracking/
├── project.yml                          # XcodeGen-Config (regeneriert .xcodeproj)
├── SimpleTracking.xcodeproj/            # Generiert — nicht manuell bearbeiten
├── privacy-policy/index.html            # Datenschutzerklärung (GitHub Pages)
│
├── Shared/                              # Code für iOS + watchOS
│   ├── WorkoutType.swift                # Enum: running, walking, cycling, hiking, ...
│   ├── WatchMessage.swift               # WorkoutMetrics (Codable), WatchCommand, Keys
│   └── UserSettings.swift              # UnitPreference, AppColorScheme, UserSettings (@Observable)
│
├── SimpleTracking/                      # iOS App
│   ├── App/
│   │   ├── SimpleTrackingApp.swift      # @main, Environment-Setup, AdMob-Init
│   │   ├── Theme.swift                  # AppChrome-Header, UserAvatarView, Farben
│   │   └── Info.plist                   # Generiert (GADApplicationIdentifier, SKAdNetworkItems, ...)
│   ├── Models/
│   │   ├── RoutePoint.swift             # GPS-Punkt (CLLocation wrapper)
│   │   ├── WorkoutRecord.swift          # Vollständiger Workout (inkl. Route)
│   │   ├── WorkoutDraft.swift           # Entwurf für manuelle Workouts
│   │   ├── WorkoutScore.swift           # Persönlicher Fitness-Score
│   │   ├── FoodEntry.swift              # Mahlzeit-Eintrag (Kalorien, Karbs, Zeitstempel)
│   │   └── QuickFoodPreset.swift        # Gespeicherte Schnell-Einträge
│   ├── Services/
│   │   ├── HealthKitService.swift       # HKHealthStore: read/write/import
│   │   ├── LocationService.swift        # CLLocationManager, Routenaufzeichnung
│   │   ├── NotificationService.swift    # UNUserNotificationCenter, km/mi-Milestone
│   │   ├── WatchConnectivityService.swift # WCSession iOS-Seite
│   │   ├── AdService.swift              # Google AdMob: Interstitial + UMP + ATT
│   │   ├── CloudKitService.swift        # STUB (reaktivierbar nach Dev Account + CloudKit)
│   │   ├── GameCenterService.swift      # GKLocalPlayer, Achievement-Reporting
│   │   ├── LocalAchievementStore.swift  # Achievement-Persistenz (UserDefaults)
│   │   ├── FoodLogStore.swift           # Ernährungslog-Persistenz
│   │   ├── FoodPhotoAnalyzer.swift      # KI-Foto-Analyse (Vision + CoreML)
│   │   ├── OpenFoodFactsService.swift   # Barcode-Scan → Nährwerte (OpenFoodFacts API)
│   │   ├── QuickFoodStore.swift         # Schnell-Einträge speichern/laden
│   │   ├── CaloricEstimator.swift       # MET-basierte Kalorienberechnung
│   │   ├── RouteCache.swift             # Route-Caching für History-Ansicht
│   │   ├── WorkoutDraftStore.swift      # Manuelle Workout-Entwürfe
│   │   └── MockDataService.swift        # Simulator-Testdaten
│   └── Views/
│       ├── ContentView.swift            # TabView (Heute, Workout, Verlauf, Statistiken, Einstellungen)
│       ├── Ads/NativeAdTile.swift       # Google Native Ad (UIViewRepresentable)
│       ├── Dashboard/DashboardView.swift
│       ├── Workout/ActiveWorkoutView.swift
│       ├── Map/RouteMapView.swift        # Live + statische Route
│       ├── Statistics/StatisticsView.swift # Charts + NativeAdTile
│       ├── History/
│       │   ├── WorkoutHistoryView.swift
│       │   └── WorkoutDetailView.swift
│       ├── Score/ScoreView.swift         # Persönlicher Fitness-Index
│       ├── Achievements/AchievementsView.swift
│       ├── Friends/FriendsView.swift     # Community (UI vorhanden, CloudKit deaktiviert)
│       ├── Food/
│       │   ├── FoodLogView.swift
│       │   ├── AddFoodSheet.swift
│       │   ├── ManualFoodEntryView.swift
│       │   ├── BarcodeEntryView.swift
│       │   └── PhotoFoodAnalysisView.swift
│       ├── Import/ImportView.swift
│       └── Settings/SettingsView.swift
│
└── SimpleTrackingWatch/                 # watchOS App
    ├── App/SimpleTrackingWatchApp.swift
    ├── Services/WatchWorkoutService.swift  # HKWorkoutSession, HKLiveWorkoutBuilder, WCSession
    └── Views/
        ├── WatchMainView.swift             # Workout-Typ-Auswahl
        └── WatchActiveWorkoutView.swift    # Live-Metriken + Pause/Stop + Haptic
```

## Datenfluss

```
Apple Watch
  └─ HKLiveWorkoutBuilder → WatchWorkoutService
        └─ WCSession.sendMessage() ──────────→ WatchConnectivityService (iOS)
                                                      └─ liveMetrics → ActiveWorkoutView

GPS (iPhone)
  └─ CLLocationManager → LocationService
        └─ recordedRoute, totalDistanceMeters → ActiveWorkoutView
              └─ NotificationService.checkMilestone() → UNUserNotificationCenter

Workout-Ende (iPhone)
  └─ HealthKitService.saveWorkout() → HKHealthStore → Apple Health
        └─ CloudKitService.publishWorkoutIfNeeded() [STUB — no-op]
        └─ GameCenterService → Achievement-Check

Ernährung
  └─ FoodLogView → AddFoodSheet
        ├─ ManualFoodEntryView (Freitext)
        ├─ BarcodeEntryView → OpenFoodFactsService (API)
        └─ PhotoFoodAnalysisView → FoodPhotoAnalyzer (Vision)
              └─ FoodLogStore → UserDefaults

Werbung
  └─ AdService (Singleton)
        ├─ UMP Consent (GDPR) → GADMobileAds
        ├─ ATT Request → AppTrackingTransparency
        ├─ Interstitial → StatisticsView (1x/Woche, max 3 Skips)
        └─ NativeAdTile → StatisticsView (inline)

Community [STUB]
  └─ CloudKitService (no-op) ←→ FriendsView (UI vorhanden)
```

## Plattform-Targets

| Target               | Min. OS      | Frameworks                                                                 |
|----------------------|--------------|----------------------------------------------------------------------------|
| SimpleTracking (iOS) | iOS 17.0     | SwiftUI, HealthKit, CoreLocation, MapKit, Swift Charts, WatchConnectivity, UserNotifications, GameKit, GoogleMobileAds, AppTrackingTransparency |
| SimpleTrackingWatch  | watchOS 10.0 | SwiftUI, HealthKit, WatchKit, WatchConnectivity, UserNotifications         |

## Werbung — AdMob

| Komponente         | Wert                                          |
|--------------------|-----------------------------------------------|
| App-ID             | ca-app-pub-9685354539860584~2584848655        |
| Native Ad Unit     | ca-app-pub-9685354539860584/5525660581        |
| Interstitial Unit  | ca-app-pub-9685354539860584/9863526692        |
| Test-Mode          | Automatisch im `#if DEBUG`-Build              |
| DSGVO              | UMP Consent Form (Google User Messaging)      |
| Tracking           | ATT-Request vor Ad-Load                       |

## Datenschutz-URL
`https://tfb74.github.io/SimpleTracker/privacy-policy/`

## State-Management
- `@Observable` + `.environment()` — kein `ObservableObject`
- `UserSettings` persistiert in `UserDefaults`
- Source of Truth für Workout-Daten: Apple Health (HKHealthStore)
- Ernährungsdaten: `FoodLogStore` → `UserDefaults`
- Achievements: `LocalAchievementStore` → `UserDefaults` + GameCenter

## Einheitensystem
- Intern: immer Meter / Meter pro Sekunde
- UI: via `UnitPreference.formatted(meters:)` in km oder miles
- Milestone-Schwelle: `UnitPreference.notificationIntervalMeters`

## Build-Hinweise
- `project.yml` ist die einzige Wahrheitsquelle — nach Änderungen `xcodegen generate`
- CloudKit: deaktiviert (kein Entitlement), Stub kompiliert ohne CloudKit-Framework
- AdMob Test-Ads: automatisch in DEBUG-Builds, keine manuelle Umschaltung nötig
- `#if os(iOS)` Guards in `UserSettings.swift` für HealthKitService-Calls (Watch-Kompatibilität)
