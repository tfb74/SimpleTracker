# Work Log — SimpleTracking

## 2026-04-19 — Meilenstein M2: Beide Targets kompilieren fehlerfrei ✅

### Fixes
- `foregroundStyle(.accentColor)` → `foregroundStyle(Color.accentColor)` in ImportView, SettingsView, WorkoutDetailView (SwiftUI akzeptiert `.accentColor` nicht als `ShapeStyle` direkt)
- XcodeGen-Entitlements-Problem gelöst: HealthKit-Properties direkt in `project.yml` unter `entitlements.properties` konfiguriert (verhindert Überschreiben beim `xcodegen generate`)
- Signing: `CODE_SIGN_STYLE: Automatic` gesetzt, `DEVELOPMENT_TEAM` bleibt leer — Xcode übernimmt Apple-ID-Team automatisch

### Build-Status
- ✅ `SimpleTracking` (iOS 17, iPhone 17 Simulator) — **BUILD SUCCEEDED**
- ✅ `SimpleTrackingWatch` (watchOS 10, Apple Watch Series 11 Simulator) — **BUILD SUCCEEDED**



## 2026-04-19 — Meilenstein M1: Basis-Setup abgeschlossen

### Erstellt
- Vollständige Projektstruktur (iOS + watchOS)
- `project.yml` für XcodeGen mit korrekten Targets, Entitlements und Info.plist-Keys
- `SimpleTracking.xcodeproj` via `xcodegen generate` generiert

### Shared
- `WorkoutType.swift` — Enum mit HealthKit-Mapping
- `WatchMessage.swift` — WorkoutMetrics (Codable), WatchCommand, Keys
- `UserSettings.swift` — UnitPreference (metric/imperial + Intervallogik), AppColorScheme (system/light/dark)

### iOS Services
- `HealthKitService.swift` — Authorization, Today-Stats, Statistiken (Tag/Woche/Monat), Workout-Laden, Route-Fetching, Speichern, Import
- `LocationService.swift` — GPS-Tracking, Distanz-Akkumulation, Milestone-Vorbereitung
- `NotificationService.swift` — UNUserNotificationCenter, km/mi-Milestone-Prüfung mit Tempo-Anzeige
- `WatchConnectivityService.swift` — WCSession iOS-Seite, Live-Metriken empfangen

### iOS Views
- `SimpleTrackingApp.swift` — @main, Environment-Injection, preferredColorScheme
- `ContentView.swift` — TabView (5 Tabs)
- `DashboardView.swift` — Heute-Übersicht, MetricCard, WorkoutRowView
- `ActiveWorkoutView.swift` — Portrait/Landscape-Layout, Live-Tracking, Milestone-Trigger
- `RouteMapView.swift` — Live-Karte (MapPolyline + UserLocation) + StaticRouteMapView
- `StatisticsView.swift` — CatmullRom-Linien + AreaMark (geglättet), Tag/Woche/Monat, Zusammenfassung
- `WorkoutHistoryView.swift` — gruppiert nach Datum
- `WorkoutDetailView.swift` — Portrait/Landscape-Layout, Route-Karte + Metriken
- `ImportView.swift` — Import aus Apple Health
- `SettingsView.swift` — Dark/Light/System-Modus, km/mi-Auswahl

### watchOS
- `WatchWorkoutService.swift` — HKWorkoutSession + HKLiveWorkoutBuilder, WCSession, Haptic-Milestone, lokale Notifications
- `SimpleTrackingWatchApp.swift` — @main, Environment
- `WatchMainView.swift` — Workout-Typ-Auswahl
- `WatchActiveWorkoutView.swift` — TimelineView, Live-Metriken, Pause/Stop

### Technische Entscheidungen
- `@Observable` statt `ObservableObject` → iOS 17+ / watchOS 10+
- Deployment Target: iOS 17.0, watchOS 10.0 (Series 4+)
- CatmullRom-Interpolation in Swift Charts für geglättete Kurven ohne Extremspitzen
- Interne Einheit immer Meter/m/s, Umrechnung nur in UnitPreference + Views
- XcodeGen verwaltet .xcodeproj (nie manuell in Xcode-Projekt-Einstellungen persistieren ohne project.yml-Update)
