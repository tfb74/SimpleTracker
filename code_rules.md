# Code Rules — SimpleTracking

## Swift-Stil
- Swift 5.9 / SwiftUI + Observation-Framework (`@Observable`)
- Keine `ObservableObject` / `@Published` — wir nutzen das neue `@Observable`-Makro
- Services sind Singletons mit `static let shared = ...` und `private init()`
- Views erhalten Services via `.environment()` / `@Environment(...)`, kein direkter Singleton-Zugriff in Views
- Kein `DispatchQueue.main.async` in Views — SwiftUI aktualisiert auf dem Main Actor automatisch; nur in Delegate-Callbacks nötig

## Architektur-Regeln
- **Keine Business-Logik in Views** — Views nur für Layout und Benutzerinteraktion
- **Services** kapseln alle HealthKit-, CoreLocation- und WatchConnectivity-Aufrufe
- **Shared-Ordner** enthält nur Code, der auf beiden Plattformen (iOS + watchOS) kompiliert
- `RoutePoint`, `WorkoutRecord` nur im iOS-Target (watchOS braucht keine Routen-Objekte)

## Keine Kommentare außer bei nicht-offensichtlichen Invarianten
- Keine "// MARK:" ohne triftigen Grund in kurzen Dateien
- Keine Erklärungen was der Code tut — nur warum, wenn es überrascht

## Einheitenlogik
- Alle internen Werte immer in **Meter** (Distanz) und **Meter/Sekunde** (Geschwindigkeit)
- Umrechnung nur in der UI und in `UnitPreference.formatted(meters:)`
- Kein `km` oder `mi` in Services oder Models

## Benachrichtigungen
- Milestone-Prüfung läuft im Workout-Timer (1-Sekunden-Intervall)
- `NotificationService.checkMilestone()` ist idempotent — der vorherige Wert wird immer mitübergeben
- Auf der Watch: erst Haptic (`WKInterfaceDevice.current().play(.notification)`), dann lokale UNNotification

## Fehlerbehandlung
- HealthKit-Fehler: `try?` in Tasks, die im Hintergrund laufen — keine Silent-Fails für kritische Writes
- CLLocationManager: Status-Enum immer in `.authorizationStatus` spiegeln

## Kein Code für hypothetische Features
- Kein generisches Protokoll für Services, wenn es nur eine Implementierung gibt
- Kein Repository-Pattern, kein Persistence-Layer über UserDefaults hinaus (Health ist die Source of Truth)
