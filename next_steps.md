# Next Steps — SimpleTracking

## Sofort möglich (kein Dev Account nötig)

### 1. Testen im Simulator
```bash
cd /Users/felix/Projects/SimpleTracking
xcodegen generate   # nach project.yml-Änderungen
open SimpleTracking.xcodeproj
```
- Scheme "SimpleTracking" → iPhone 17 Simulator → Run
- Ads erscheinen als Test-Ads (automatisch im DEBUG-Build)
- AdMob Debug-Controls unter Einstellungen → Werbung

### 2. AdMob Datenschutz-URL hinterlegen
- admob.google.com → Apps → SimpleTracker → App-Einstellungen
- Datenschutz-URL: `https://tfb74.github.io/SimpleTracker/privacy-policy/`

### 3. AdMob DSGVO-Nachricht konfigurieren
- admob.google.com → Datenschutz & Messaging → GDPR → Nachricht erstellen
- Eigene Consent-Message anlegen (Pflicht für EU-Traffic)

### 4. AdMob Zahlungsprofil vervollständigen
- admob.google.com → Zahlungen → Zahlungsprofil
- Name, Adresse, Steuer-Identifikationsnummer (persönliche IdNr.) eintragen
- Auszahlungsmethode (IBAN) hinterlegen

---

## Sobald Apple Developer Account aktiv ist

### 5. DEVELOPMENT_TEAM eintragen
```yaml
# project.yml — beide Targets:
DEVELOPMENT_TEAM: "DEIN10ZEICHENID"
```
```bash
xcodegen generate
```
Team-ID findest du unter: developer.apple.com → Account → Membership

### 6. App Store Connect: App anlegen
- appstoreconnect.apple.com → Apps → + → Neue App
- Bundle ID: `com.felix.SimpleTracking`
- Name: `SimpleTracker` (prüfen ob verfügbar)
- Primäre Sprache: Deutsch
- SKU: `simpletracker-ios-2026`
- Alle Metadaten aus `app_store_metadata.md` übernehmen

### 7. Auf echtem Gerät testen (Abnahmekriterien)
- [ ] App startet ohne Crash auf iPhone
- [ ] HealthKit-Berechtigungen erscheinen + bestätigt
- [ ] Standort "Immer erlauben" gesetzt
- [ ] Watch-App sichtbar + startet
- [ ] Live-Metriken Watch → iPhone funktionieren
- [ ] Workout beenden → Eintrag in Apple Health
- [ ] AdMob UMP-Consent-Dialog erscheint beim ersten Start
- [ ] Test-Ad lädt in Statistik-Tab

### 8. Screenshots erstellen
- iPhone 6.9" (iPhone 16 Pro Max): 5 Screenshots
- iPhone 6.5" (iPhone 14 Plus): 5 Screenshots  
- Apple Watch 46mm: 3 Screenshots
- Reihenfolge: Dashboard → Workout aktiv → Karte → Statistik → Ernährung

### 9. Archive + Upload
- Xcode → Product → Archive
- Organizer → Distribute App → App Store Connect → Upload
- Danach in App Store Connect: Build auswählen + einreichen

### 10. AdMob: App Store URL eintragen
- Nach Veröffentlichung: admob.google.com → Apps → App Store URL hinterlegen
- Echte Ads werden dann vollständig ausgespielt

---

## Nach App Store Live

### 11. CloudKit reaktivieren (M5)
- Xcode → Signing & Capabilities → + Capability → CloudKit
- CloudKit Dashboard: Record-Typen anlegen
  - `STUserProfile`: friendCode (String), displayName (String), avatarPreset (String)
  - `STActivity`: friendCode (String), displayName (String), avatarPreset (String),
    eventType (String), eventTitle (String), eventDetail (String),
    workoutTypeRaw (String), timestamp (Date)
- `CloudKitService.swift` aus Git-History wiederherstellen:
  ```bash
  git show HEAD~1:SimpleTracking/Services/CloudKitService.swift > CloudKitService.swift
  ```
- `project.yml`: CloudKit-Entitlement wieder hinzufügen
- Update pushen → App Store Update einreichen
