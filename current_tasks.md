# Current Tasks — SimpleTracking

> Meilenstein: **M3 — Erstes Deployment auf echtem Gerät + Live-Test**

## Status
- ✅ M1: Basis-Setup abgeschlossen (alle Dateien, XcodeGen-Projekt)
- ✅ M2: Beide Targets kompilieren fehlerfrei (iOS + watchOS Simulator)

## Offen

### Signing für echtes Gerät
- [ ] Xcode öffnen → Projekt-Target „SimpleTracking" → Signing & Capabilities → Apple ID auswählen
- [ ] Gleiches für „SimpleTrackingWatch"
- [ ] iPhone + Watch per USB anschließen, Scheme anpassen, Run

### Erster Live-Test (Abnahmekriterien M3)
- [ ] App startet auf iPhone ohne Crash
- [ ] HealthKit-Berechtigungsdialog erscheint + wird bestätigt
- [ ] Standort-Berechtigungsdialog erscheint + „Immer erlauben" gewählt
- [ ] Watch-App ist auf der Watch sichtbar
- [ ] Workout auf Watch starten → Live-Metriken erscheinen auf iPhone
- [ ] 1 km zurücklegen → Benachrichtigung auf iPhone + Haptic auf Watch
- [ ] Workout beenden → Eintrag in Apple Health-App sichtbar
- [ ] Import-Tab öffnen → bisherige Workouts erscheinen als Liste

### Bekannte Einschränkungen (für M3 akzeptiert)
- Schritte beim iPhone-GPS-Workout: fest auf „--" (HKPedometer-Integration kommt in M4)
- Kalorien bei iPhone-Workout: Schätzwerte, nicht aus HKWorkoutSession
- Landscape auf Watch: nicht unterstützt (watchOS-Systembeschränkung)
