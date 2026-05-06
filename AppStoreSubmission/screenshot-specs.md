# Screenshot-Spezifikationen

Apple verlangt für die App-Submission Screenshots in **mindestens einer** Display-Größe pro Plattform. Wenn du eine Größe machst, skaliert Apple automatisch für andere Geräte – aber sauberer ist es zwei zu liefern.

## iPhone (Pflicht)

Mache Screenshots auf **mindestens diesem Gerät**:

### iPhone 17 Pro Max (6.9-inch) – 1290×2796 px
- Pflichtgrösse für 6.9"-Display.
- Mache mindestens 3, idealerweise 5–10 Screenshots.

### iPhone 8 Plus (5.5-inch) – 1242×2208 px (optional)
- Wenn du auch ältere iPhones unterstützen willst.
- Apple empfiehlt diese Größe als Fallback.

## iPad (nur falls iPad-Support)

### iPad Pro 13" – 2064×2752 px

## Apple Watch (Pflicht da Watch-App im Bundle)

### Series 10 (46mm) – 416×496 px

## Welche Screens fotografieren

Empfohlene 6 Screenshots in dieser Reihenfolge (Apple's "First impression"-Logik):

1. **Dashboard** – Tagesübersicht mit Schritten, Kalorien, Distanz
2. **Active Workout mit Karte** – GPS-Tracking läuft, Karte sichtbar mit Route + Live-Metriken
3. **Foto-Analyse Ergebnis** – Mahlzeit fotografiert, KI hat Komponenten erkannt
4. **Manuelle Mahlzeit mit KI-Vorschlag** – Beispiel "Spaghetti Bolognese" mit Vorschlag-Banner
5. **Workout-Verlauf** – Liste der letzten Workouts gruppiert nach Datum
6. **Statistiken** – Wochenchart oder Monatsübersicht

## Wie aufnehmen

### Option A: Echtes iPhone (empfohlen)
1. iPhone 17 Pro Max oder 17 Pro Max Simulator nutzen
2. App im Release-Build laufen lassen (Test-Daten ggf. via Settings → Mock-Daten generieren)
3. Hardware-Buttons: **Power + Lautstärke-Hoch** gleichzeitig
4. Screenshots werden in Fotos gespeichert → über AirDrop oder iCloud auf den Mac

### Option B: Simulator
1. Simulator starten (iPhone 17 Pro Max, iOS 26)
2. App laufen lassen
3. **Cmd + S** für Screenshot, oder File → New Screen Shot
4. Wird auf den Desktop gelegt

## Nach dem Aufnehmen

1. Sortieren in der gewünschten Reihenfolge (1.png, 2.png, ...)
2. Optional: in Figma/Sketch in Marketing-Frames packen mit Untertiteln
3. In ASC hochladen unter "App Store" → "Version" → "Screenshots"

## Apple-Regeln (wichtig)

- **Keine Status-Bar manipulieren** – iOS 26 zeigt automatisch "9:41" und volle Batterie als Demo-Werte
- **Keine Konkurrenz-Apps** in Screenshots zeigen
- **Keine Apple-Logos in Marketingstil**
- **Personenfotos** im Foto-Analyse-Screenshot vermeiden (rechtlich heikel) – stattdessen klar erkennbares Essen
- **Kein Mock-Up von Apple-Devices** im Screenshot selbst (Apple zeigt das Device-Frame schon im Store)
