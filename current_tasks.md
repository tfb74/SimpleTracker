# Current Tasks — SimpleTracking

> Meilenstein: **M4 — App Store Submission**
> Blocker: Apple Developer Account in Review (seit ~8h, 22.04.2026)

## Status
- ✅ M1: Basis-Setup (iOS + watchOS, alle Core-Features)
- ✅ M2: Beide Targets kompilieren fehlerfrei (Simulator)
- ✅ M3: Feature-Vollständigkeit (Ads, Food, Score, Achievements, Friends-Stub)
- 🔄 M4: App Store Submission — wartet auf Dev Account

## Erledigt heute (22.04.2026)
- [x] CloudKitService durch Stub ersetzt (kein CloudKit-Entitlement nötig)
- [x] Watch-Build-Fehler gefixt (`#if os(iOS)` um HealthKitService-Calls in UserSettings)
- [x] Datenschutzerklärung erstellt (HTML, responsive, DSGVO-konform)
- [x] GitHub Repository angelegt: github.com/tfb74/SimpleTracker
- [x] Gesamtes Projekt auf GitHub gepusht
- [x] GitHub Pages aktiviert → Datenschutz-URL live
- [x] MARKETING_VERSION "1.0" + CURRENT_PROJECT_VERSION "1" in project.yml
- [x] App Store Metadaten-Dokument erstellt (app_store_metadata.md)
- [x] Alle MD-Files aktualisiert

## Offen — wartet auf Dev Account
- [ ] DEVELOPMENT_TEAM in project.yml eintragen
- [ ] xcodegen regenerieren
- [ ] App auf echtem iPhone + Watch abnehmen (Abnahmekriterien in next_steps.md)
- [ ] App Store Connect: App-Eintrag anlegen
- [ ] Screenshots erstellen (6.9", 6.5", Watch 46mm)
- [ ] Archive + Upload via Xcode Organizer

## Offen — sofort möglich (kein Dev Account nötig)
- [ ] AdMob: Datenschutz-URL hinterlegen (`https://tfb74.github.io/SimpleTracker/privacy-policy/`)
- [ ] AdMob: DSGVO-Consent-Nachricht konfigurieren
- [ ] AdMob: Zahlungsprofil + Steuer-ID + IBAN eintragen

## Bekannte Einschränkungen (für 1.0 akzeptiert)
- CloudKit/Friends: deaktiviert (reaktivierung nach Dev Account, M5)
- Schritte beim iPhone-GPS-Workout: Schätzwert (HKPedometer kommt in M6)
- Kalorien bei iPhone-Workout: Schätzwert aus CaloricEstimator
- Landscape auf Watch: nicht unterstützt (watchOS-Systembeschränkung)
- Watch-Face Complication: nicht vorhanden (kommt M6)
