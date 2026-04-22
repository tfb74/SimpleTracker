# Next Steps — SimpleTracking

## Sofort (Meilenstein M2 freischalten)

### 1. Team-ID konfigurieren
Öffne `project.yml` und trage deine Apple Developer Team-ID ein:
```yaml
settings:
  DEVELOPMENT_TEAM: "ABCDE12345"   # ← deine 10-stellige Team-ID
```
Dann `xcodegen generate` im Projektordner ausführen.

### 2. Erstes Build & Test auf Gerät
```bash
cd /Users/felix/Projects/SimpleTracking
xcodegen generate   # immer nach project.yml-Änderungen!
open SimpleTracking.xcodeproj
```
In Xcode:
- Scheme "SimpleTracking" → dein iPhone → Run
- Scheme "SimpleTrackingWatch" → deine Watch → Run

### 3. Berechtigungen on-device bestätigen
- HealthKit: alle Kategorien erlauben
- Standort: "Immer erlauben" (für Hintergrund-GPS)
- Benachrichtigungen: erlauben

## Meilenstein M2 — Prüfkriterien
Meilenstein gilt als erreicht wenn:
1. App startet ohne Crash auf iPhone + iPad
2. Workout (laufen/gehen) auf Watch startbar
3. Live-Metriken erscheinen auf iPhone während Watch-Workout
4. Nach 1 km erscheint Benachrichtigung auf beiden Geräten
5. Workout-Ende speichert Eintrag in Apple Health
6. Import-Tab lädt alle bisherigen Workouts aus Apple Health

## Mittelfristig (M3)

### HKPedometer für echte Schrittzählung beim iPhone-Workout
```swift
// In LocationService oder separatem PedometerService
import CoreMotion
let pedometer = CMPedometer()
pedometer.startUpdates(from: Date()) { data, _ in
    self.steps = Int(data?.numberOfSteps ?? 0)
}
```

### Watch-Face Complication
- `WidgetKit`-Extension dem Watch-Target hinzufügen
- Tages-Schritte als Complication-Wert

### Laps / Kilometerzeiten
- Pro Milestone-Event einen `LapRecord` speichern
- In `WorkoutDetailView` als Liste anzeigen

## Langfristig (M4)

### iPad Split-View
```swift
NavigationSplitView {
    WorkoutHistoryView()
} detail: {
    WorkoutDetailView(workout: selected)
}
```

### Wochenziel
- In `UserSettings` ein tägliches Schrittziel speichern
- In `DashboardView` als Fortschrittsring anzeigen (analog Activity-Ringe)
