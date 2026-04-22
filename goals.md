# Goals — SimpleTracking

## Milesteine

### M1 — Basis-Setup ✅ (aktuell abgeschlossen)
- [x] Vollständige Projektstruktur (iOS + watchOS Targets)
- [x] Xcode-Projekt via XcodeGen generiert
- [x] Alle Swift-Quelldateien angelegt und kompilierbar
- [x] HealthKit-Integration (lesen + schreiben)
- [x] CoreLocation GPS-Tracking mit Routenaufzeichnung
- [x] MapKit-Routendarstellung (live + statisch)
- [x] Swift Charts mit CatmullRom-Interpolation (geglättete Linien)
- [x] km/Meilen-Benachrichtigungen auf iPhone und Watch
- [x] Dark-/Light-/System-Mode-Unterstützung
- [x] Metrisch/Imperial-Einheitenauswahl
- [x] Apple Health Import
- [x] WatchConnectivity (Live-Metriken Watch → iPhone)

### M2 — Erste lauffähige Version (nächster Meilenstein)
- [ ] Team-ID in project.yml eintragen und Signing konfigurieren
- [ ] Auf echtem iPhone compilieren (ohne Fehler)
- [ ] Auf echter Watch deployen und Workout starten
- [ ] HealthKit-Berechtigungen auf Gerät bestätigen
- [ ] Erster Test: Workout starten, Kilometer-Benachrichtigung empfangen
- [ ] Import-Flow testen: Apple Health Daten laden + anzeigen

### M3 — Statistiken & Polish
- [ ] Wochenziel (Schritt-/Distanz-Ziel) setzen
- [ ] Complication auf Watch-Face (aktueller Tagesziel-Fortschritt)
- [ ] Workout-Typen um Schwimmen + Krafttraining erweitern
- [ ] Laps / Rundenzeiten pro km/Meile

### M4 — iPad-Optimierung
- [ ] Split-View auf iPad (Sidebar + Detail)
- [ ] Larger-Display-Charts mit mehr Datenpunkten
- [ ] Multi-Window-Support

## Qualitätsziele
- Keine externen Abhängigkeiten (reines Apple-Ökosystem)
- Keine bezahlten APIs
- Deployment Target: iOS 17+, watchOS 10+
- Sprache: Deutsch (UI), Swift 5.9
