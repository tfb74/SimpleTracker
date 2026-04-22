# Work Log — SimpleTracking

## 2026-04-22 — Meilenstein M3 abgeschlossen + M4 vorbereitet ✅

### Ziel
App Store Submission vorbereiten, solange Apple Developer Account in Review ist.

### Infrastruktur
- GitHub Repository angelegt: github.com/tfb74/SimpleTracker (Public)
- `.gitignore` erstellt (Xcode-Standard: DerivedData, xcuserdata, build/)
- Gesamtes Projekt gepusht (119 Objekte, 1.24 MiB)
- GitHub Pages aktiviert → Branch: main, Ordner: / (root)

### Datenschutzerklärung
- `privacy-policy/index.html` erstellt — vollständige DSGVO-konforme Datenschutzerklärung
- Abgedeckt: HealthKit, GPS, AdMob, ATT, CloudKit (Community), Game Center, WatchConnectivity
- URL live: `https://tfb74.github.io/SimpleTracker/privacy-policy/`
- Link in SettingsView eingebaut (Abschnitt "Rechtliches")

### Build-Fixes
- `CloudKitService.swift`: Echte CloudKit-Implementierung durch Stub ersetzt
  - Entfernt: `import CloudKit`, alle `CKContainer`/`CKDatabase`/`CKRecord`-Aufrufe
  - Beibehalten: alle public Properties + Methoden-Signaturen (gleiche API)
  - Grund: CloudKit-Capability erfordert bezahlten Developer Account
  - Reaktivierung: nach Dev Account, CloudKit Capability + echte Impl. aus Git-History
- `UserSettings.swift`: `#if os(iOS)` Guards um HealthKitService-Calls
  - `writeBodyMass(kg:)` und `writeHeight(cm:)` nur auf iOS kompiliert
  - Verhindert Watch-Build-Fehler ("Cannot find 'HealthKitService' in scope")

### Versioning
- `MARKETING_VERSION: "1.0"` in beiden Targets (project.yml)
- `CURRENT_PROJECT_VERSION: "1"` in beiden Targets (project.yml)

### Dokumentation
- `goals.md`: M3 als abgeschlossen markiert, M4/M5/M6 neu definiert
- `next_steps.md`: Komplett neu geschrieben — strukturiert nach "sofort möglich" vs. "nach Dev Account"
- `current_tasks.md`: Auf M4 aktualisiert, Tages-Log ergänzt
- `architecture.md`: Komplett neu — alle Services, Views, Datenfluss, AdMob-Konfiguration
- `app_store_metadata.md`: Neu erstellt — App Store Beschreibung DE+EN, Keywords, Metadaten

### App Store Metadaten (vorbereitet)
- App-Name: SimpleTracker
- Kategorie: Gesundheit & Fitness
- Altersfreigabe: 4+
- Vollständige Beschreibung (DE + EN) in app_store_metadata.md
- 30 Keywords definiert

---

## 2026-04-19 — Meilenstein M2: Beide Targets kompilieren fehlerfrei ✅

### Fixes
- `foregroundStyle(.accentColor)` → `foregroundStyle(Color.accentColor)` in ImportView, SettingsView, WorkoutDetailView
- XcodeGen-Entitlements-Problem gelöst: HealthKit-Properties direkt in `project.yml`
- Signing: `CODE_SIGN_STYLE: Automatic`, `DEVELOPMENT_TEAM` leer

### Build-Status
- ✅ `SimpleTracking` (iOS 17, iPhone 17 Simulator) — BUILD SUCCEEDED
- ✅ `SimpleTrackingWatch` (watchOS 10, Apple Watch Series 11 Simulator) — BUILD SUCCEEDED

---

## 2026-04-19 — Meilenstein M1: Basis-Setup abgeschlossen

### Erstellt
- Vollständige Projektstruktur (iOS + watchOS)
- `project.yml` für XcodeGen
- `SimpleTracking.xcodeproj` via `xcodegen generate`

### Shared
- `WorkoutType.swift`, `WatchMessage.swift`, `UserSettings.swift`

### iOS Services
- HealthKitService, LocationService, NotificationService, WatchConnectivityService

### iOS Views
- SimpleTrackingApp, ContentView, DashboardView, ActiveWorkoutView, RouteMapView
- StatisticsView, WorkoutHistoryView, WorkoutDetailView, ImportView, SettingsView

### watchOS
- WatchWorkoutService, SimpleTrackingWatchApp, WatchMainView, WatchActiveWorkoutView

### Technische Entscheidungen
- `@Observable` statt `ObservableObject` → iOS 17+ / watchOS 10+
- Deployment Target: iOS 17.0, watchOS 10.0
- CatmullRom-Interpolation in Swift Charts
- Interne Einheit immer Meter/m/s
- XcodeGen als einzige Projektquelle
