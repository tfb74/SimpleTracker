# Goals — SimpleTracking

## Milesteine

### M1 — Basis-Setup ✅
- [x] Vollständige Projektstruktur (iOS + watchOS Targets)
- [x] Xcode-Projekt via XcodeGen generiert
- [x] HealthKit-Integration (lesen + schreiben)
- [x] CoreLocation GPS-Tracking mit Routenaufzeichnung
- [x] MapKit-Routendarstellung (live + statisch)
- [x] Swift Charts mit CatmullRom-Interpolation
- [x] km/Meilen-Benachrichtigungen auf iPhone und Watch
- [x] Dark-/Light-/System-Mode-Unterstützung
- [x] Metrisch/Imperial-Einheitenauswahl
- [x] Apple Health Import
- [x] WatchConnectivity (Live-Metriken Watch → iPhone)

### M2 — Beide Targets kompilieren ✅
- [x] iOS + watchOS Target fehlerfrei im Simulator
- [x] XcodeGen-Signing konfiguriert (Automatic, kein hardcodiertes Team)
- [x] Alle Swift-Quelldateien kompilierbar

### M3 — Feature-Vollständigkeit ✅
- [x] Ernährungstracking (FoodLog, Barcode-Scan, Foto-Analyse)
- [x] Workout-Score (persönlicher Fitness-Index)
- [x] Game Center Achievements (18 Achievements)
- [x] Google AdMob (Native Tile + Interstitial, UMP-Consent, ATT)
- [x] Friends/Community-Feature (CloudKit, aktuell deaktiviert bis Dev Account)
- [x] Custom AppChrome Header (Theme, UserAvatarView)
- [x] Datenschutzerklärung (GitHub Pages: tfb74.github.io/SimpleTracker/privacy-policy/)
- [x] GitHub-Repository angelegt und gepusht
- [x] App Version 1.0 / Build 1 gesetzt

### M4 — App Store Submission (aktuell blockiert: Dev Account in Review)
- [ ] Apple Developer Account aktiv
- [ ] App Store Connect: App-Eintrag anlegen (Bundle ID, Name, Kategorie)
- [ ] DEVELOPMENT_TEAM in project.yml eintragen + xcodegen regenerieren
- [ ] App auf echtem iPhone + Watch testen und abnehmen
- [ ] App Store Screenshots erstellen (iPhone 6.9", 6.5", Watch 46mm)
- [ ] App Store Connect: Beschreibung, Keywords, Support-URL, Datenschutz-URL eintragen
- [ ] AdMob: App Store URL hinterlegen → echte Ads freischalten
- [ ] Archive + Upload via Xcode Organizer
- [ ] App Review einreichen

### M5 — Post-Launch: CloudKit & Friends reaktivieren
- [ ] Dev Account aktiv → CloudKit Capability wieder einschalten
- [ ] CloudKit Dashboard: Record-Typen "STUserProfile" + "STActivity" anlegen
- [ ] CloudKitService.swift: echte Implementierung wiederherstellen (aus Git-History)
- [ ] FriendsView testen mit zwei Geräten
- [ ] CloudKit-Abschnitt in Datenschutzerklärung ist bereits vorhanden ✅

### M6 — iPad & Widgets
- [ ] Split-View auf iPad (NavigationSplitView)
- [ ] Watch-Face Complication (WidgetKit)
- [ ] Landscape-optimierte Charts mit mehr Datenpunkten

## Qualitätsziele
- Keine externen Server (reines Apple-Ökosystem + AdMob)
- Deployment Target: iOS 17+, watchOS 10+
- Swift 5.9, @Observable Pattern
- Lokalisierung: DE, EN, ES, FR
