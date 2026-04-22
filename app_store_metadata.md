# App Store Metadaten — SimpleTracker

## Grunddaten
| Feld                  | Wert                                          |
|-----------------------|-----------------------------------------------|
| App-Name              | SimpleTracker                                 |
| Bundle ID             | com.felix.SimpleTracking                      |
| SKU                   | simpletracker-ios-2026                        |
| Primäre Kategorie     | Gesundheit & Fitness                          |
| Sekundäre Kategorie   | Sport                                         |
| Altersfreigabe        | 4+                                            |
| Preis                 | Kostenlos                                     |
| Primäre Sprache       | Deutsch                                       |
| Version               | 1.0                                           |
| Copyright             | © 2026 Felix Baumann                          |
| Support-URL           | https://github.com/tfb74/SimpleTracker        |
| Datenschutz-URL       | https://tfb74.github.io/SimpleTracker/privacy-policy/ |

---

## App-Beschreibung (Deutsch) — max. 4000 Zeichen

SimpleTracker ist dein persönlicher Fitness-Begleiter für iPhone und Apple Watch — kompakt, schnell und vollständig privat.

**Deine Daten gehören dir.**
Alle Trainingsdaten, GPS-Routen und Gesundheitswerte bleiben ausschließlich auf deinem Gerät und in Apple Health. Kein Cloud-Abo, kein Login, kein fremder Server.

**Was SimpleTracker kann:**

🏃 WORKOUT-TRACKING
Starte Trainings direkt auf der Apple Watch oder dem iPhone. GPS zeichnet deine Route in Echtzeit auf. Live-Metriken (Tempo, Distanz, Kalorien, Herzfrequenz) erscheinen sofort auf beiden Geräten.

📍 GPS & KARTE
Deine gelaufene Route wird als geglättete Linie auf der Karte angezeigt — sowohl live während des Workouts als auch nachträglich in der Workout-Übersicht.

📊 STATISTIKEN
Analysiere deinen Fortschritt mit eleganten Diagrammen: Schritte, Distanz, Kalorien — täglich, wöchentlich oder monatlich. Geglättete Linien machen Trends auf einen Blick sichtbar.

🍎 ERNÄHRUNG
Verfolge Kalorien und Kohlenhydrate. Scanne Barcodes direkt aus dem Supermarkt, analysiere Mahlzeiten per Foto oder trage Werte manuell ein.

🏆 ACHIEVEMENTS
Schalte Erfolge frei und tracke deinen persönlichen Fitness-Score — basierend auf Alter, Gewicht, Körpergröße und deiner tatsächlichen Aktivität.

⌚ APPLE WATCH
Die Watch-App startet Workouts komplett eigenständig. Kilometer-Benachrichtigungen mit aktuellem Tempo kommen als Haptic-Feedback direkt ans Handgelenk.

📥 HEALTH-IMPORT
Importiere all deine bisherigen Workouts aus Apple Health — egal ob sie mit der Apple Watch, Fitness+ oder anderen Apps aufgezeichnet wurden.

---

## App-Beschreibung (Englisch)

SimpleTracker is your personal fitness companion for iPhone and Apple Watch — clean, fast, and completely private.

**Your data stays yours.**
All workout data, GPS routes and health metrics stay exclusively on your device and in Apple Health. No subscription, no login, no third-party server.

**What SimpleTracker does:**

🏃 WORKOUT TRACKING
Start workouts directly on Apple Watch or iPhone. GPS records your route in real time. Live metrics (pace, distance, calories, heart rate) appear instantly on both devices.

📍 GPS & MAP
Your route is displayed as a smooth line on the map — live during your workout and afterward in your history.

📊 STATISTICS
Analyze your progress with elegant charts: steps, distance, calories — daily, weekly or monthly.

🍎 NUTRITION
Track calories and carbohydrates. Scan barcodes, analyze meals by photo, or enter values manually.

🏆 ACHIEVEMENTS
Unlock achievements and track your personal fitness score — based on age, weight, height and your actual activity.

⌚ APPLE WATCH
The Watch app runs workouts independently. Kilometer alerts with current pace arrive as haptic feedback on your wrist.

📥 HEALTH IMPORT
Import all your existing workouts from Apple Health.

---

## Keywords (max. 100 Zeichen, kommagetrennt)
```
fitness,tracker,workout,laufen,gehen,radfahren,gps,route,kalorien,schritte,apple watch,health,sport
```

## Was zu überprüfen ist in App Store Connect

### App-Datenschutz (Privacy Nutrition Label)
Folgende Daten werden erhoben:
- **Daten die nicht mit dir verknüpft sind**: Geräte-ID (für Werbung, AdMob)
- **Daten die nicht gesammelt werden**: Gesundheitsdaten, Standort, Name, E-Mail

### Werbeinhalt
- Enthält Werbung: ✅ Ja (Google AdMob)
- Datenschutz-URL: `https://tfb74.github.io/SimpleTracker/privacy-policy/`

### Berechtigungen (werden im Review erklärt)
- HealthKit: Workouts lesen/schreiben, Schritte, Kalorien, Gewicht
- Standort (immer): GPS-Tracking im Hintergrund während aktivem Workout
- Kamera: Barcode-Scan + Foto-Analyse für Ernährungstracking
- Tracking (ATT): Personalisierte Werbung (optional, Nutzer kann ablehnen)

### Screenshots-Reihenfolge (empfohlen)
1. Dashboard — Heute-Übersicht mit Schritte/Kalorien/Distanz
2. Aktives Workout — Live-Karte + Metriken
3. Statistiken — Wochendiagramm
4. Ernährungslog
5. Achievements / Score

### Hinweis für App Review
"Die App enthält Google AdMob-Werbung. Der DSGVO-Consent-Dialog erscheint beim ersten Start.
Game Center-Integration: Achievements werden lokal + über Game Center getrackt.
CloudKit (Freunde-Feature) ist in dieser Version deaktiviert und für ein zukünftiges Update vorgesehen."
