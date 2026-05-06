# SimpleTracking – App Store Submission Checklist

Komplette Reihenfolge der Schritte. Alles abhaken, dann ist die App live.

## A) App in App Store Connect anlegen

1. https://appstoreconnect.apple.com/apps öffnen
2. Klick **+** → **New App**
3. Felder:
   - **Platforms:** iOS (Watch ist im Bundle, kein separater Eintrag)
   - **Name:** `SimpleTracking`
   - **Primary Language:** German
   - **Bundle ID:** `de.baumannheim.SimpleTracking` (sollte in der Dropdown-Liste auftauchen)
   - **SKU:** `simpletracking-001` (frei wählbar, intern)
   - **User Access:** Full Access
4. Create klicken

## B) App Information ausfüllen

In ASC: deine App → **App Information**

- [ ] **Subtitle (DE/EN):** `Workout, Ernährung, Schritte` / `Workout, Nutrition, Steps` (max. 30 Zeichen)
- [ ] **Privacy Policy URL:** `https://github.com/tfb74/SimpleTracker/tree/main/privacy-policy/index.html` (besser eine direkte URL zur HTML, nicht zum Tree – siehe Hinweis unten)
- [ ] **Category Primary:** Health & Fitness
- [ ] **Category Secondary:** Sports
- [ ] **Content Rights:** „Does not contain, show, or access third-party content" (außer du hast einen Drittanbieter wie OpenFoodFacts gelistet – ggf. anpassen)

> **Hinweis Privacy Policy URL:** GitHub-Tree-Links sind nicht ideal, weil sie das GitHub-UI zeigen statt die Policy direkt. Besser:
> - GitHub Pages aktivieren in dem Repo, dann hat die HTML eine eigene URL wie `https://tfb74.github.io/SimpleTracker/privacy-policy/`
> - Oder die index.html via raw-Link: `https://raw.githubusercontent.com/tfb74/SimpleTracker/main/privacy-policy/index.html` (rendert aber als Plaintext, nicht ideal)
> - **Beste Lösung:** GitHub Pages für das Repo aktivieren

## C) Pricing and Availability

- [ ] **Price Schedule:** Free
- [ ] **Availability:** alle Länder oder gezielt DACH

## D) Version 1.0 Inhalte (App Store → Version-Block)

- [ ] **What's New in This Version:** aus `whats-new-de.txt` / `whats-new-en.txt`
- [ ] **Promotional Text:** aus `promotional-text-*.txt`
- [ ] **Description:** aus `app-description-*.txt`
- [ ] **Keywords:** aus `keywords-*.txt`
- [ ] **Support URL:** dein GitHub-Repo oder Mailto-Link
- [ ] **Marketing URL:** optional
- [ ] **Screenshots:** gemäß `screenshot-specs.md` aufnehmen und hochladen
- [ ] **App Icon:** wird automatisch aus dem Bundle gezogen
- [ ] **Copyright:** `© 2026 Felix Baumann`
- [ ] **Routing App Coverage File:** überspringen (nicht relevant)

## E) App Privacy

In ASC → **App Privacy** → **Get Started**

Sammlung deklarieren (basierend auf dem aktuellen Code):
- [ ] **Health and Fitness:** Workouts, Schritte, Herzfrequenz, Kalorien (Apple Health)
- [ ] **Location:** Precise Location (für GPS-Tracking) – „App Functionality"
- [ ] **Photos:** Photos taken in app (Foto-Analyse) – wird nur lokal verarbeitet
- [ ] **Identifiers:** Device ID (für AdMob)
- [ ] **Usage Data:** Product Interaction (für AdMob, falls User ATT zustimmt)

Für jede Kategorie auswählen:
- Linked to User: NEIN (alles bleibt anonym/lokal)
- Used for Tracking: JA für Identifiers (AdMob), sonst NEIN

## F) Game Center Setup

In ASC → deine App → **Services** → **Game Center**

- [ ] **Enable Game Center**
- [ ] **Achievements:** 14 Stück anlegen aus `gamecenter-achievements.csv`
  - Pro Achievement Image Upload nötig (512×512 PNG, einfacher Achievement-Badge reicht)
- [ ] **Leaderboards:** 4 Stück anlegen aus `gamecenter-leaderboards.csv`

> **Tipp Achievements-Bild:** Apple verlangt für jedes Achievement ein Bild. Du kannst eines pro Stück bauen (in Figma/Canva) oder ein einziges generisches "Trophy"-PNG für alle benutzen. Pflicht: 512×512 PNG, RGB, weniger als 1MB.

## G) AdMob – App Store ID hinterlegen

Sobald der App-Eintrag in ASC steht, hat deine App eine **numerische App Store ID** (siehe oben in App Information, Format: `1234567890`).

1. https://apps.admob.com → Apps → SimpleTracking
2. App-Settings → App Store
3. App Store ID einfügen
4. Speichern

## H) Build hochladen

In Xcode:
1. Run-Target auf **Any iOS Device (arm64)** wechseln
2. **Product → Archive**
3. Im Organizer: Archive auswählen → **Distribute App** → **App Store Connect** → **Upload**
4. Folgen, signieren lassen, hochladen
5. Nach 5–30 Min taucht der Build in ASC unter Version 1.0 → Build auf

## I) Build mit Version verknüpfen

In ASC → Version 1.0 → Build → den hochgeladenen Build auswählen

## J) Export Compliance

Bei der ersten Version fragt Apple nach Verschlüsselung:
- [ ] **Uses Non-Exempt Encryption:** NO (Standard-iOS-Crypto reicht aus, keine Custom-Crypto in der App)

## K) Submit for Review

- [ ] **Demo Account:** falls Game-Center-Sync getestet werden soll, ggf. einen Sandbox-Tester anlegen und Logindaten in „Notes" hinterlegen
- [ ] **Notes:** Hinweis für Reviewer wie z.B. "App requires HealthKit and Location permissions for workout tracking. Photo analysis uses on-device Apple Intelligence (iOS 26)."
- [ ] Klick **Add for Review** → **Submit for Review**

## L) Warten und reagieren

- 1–3 Werktage Review-Zeit
- Wenn Approved: optional auf "Manual Release" setzen oder direkt automatisch live
- Falls Rejected: Begründung lesen, beheben, neu submitten

## Letzte Sanity-Checks vor Submission

- [ ] App auf echtem iPhone gebaut und Hauptfunktionen getestet
- [ ] Alle Sprachversionen (DE + EN) durchgeklickt
- [ ] Crash-Test: 5 Min normal benutzen, kein Crash
- [ ] Ad-Banner erscheint (Test-Mode reicht für Submission)
- [ ] Health-Permissions werden sauber abgefragt
- [ ] Location-Permission wird mit klarer Begründung gezeigt
- [ ] App Icon sieht auf Homescreen gut aus
- [ ] Watch-App startet und zeigt Workout-Screen
