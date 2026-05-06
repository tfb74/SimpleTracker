# Universal Links – Hosting-Setup

## Was du erreichen willst

Wenn jemand in iMessage einen Link wie  
`https://tfb74.github.io/SimpleTracker/friend?code=ABC-123` bekommt:

- **Mit App installiert:** Tap → SimpleTracking öffnet direkt im „Freund hinzufügen"-Sheet
- **Ohne App installiert:** Tap → Landing-Page mit Code + App-Store-Button
- **In der Nachricht selbst:** Rich Preview mit App-Icon + Titel + Beschreibung

## ⚠️ Wichtige Vorraussetzung

Apple verlangt die `apple-app-site-association`-Datei **am Wurzelpfad der Domain** unter `/.well-known/`.

Das heißt für deine Domain `tfb74.github.io`:
- ✅ `https://tfb74.github.io/.well-known/apple-app-site-association`
- ❌ `https://tfb74.github.io/SimpleTracker/.well-known/apple-app-site-association` (funktioniert NICHT!)

GitHub Pages-Project-Sites (deine `tfb74/SimpleTracker`) haben aber den Pfad `/SimpleTracker/`. Du brauchst also **Zugriff auf den Domain-Wurzelpfad**.

### Drei Möglichkeiten

**Option A — User-Site-Repo (einfachste, empfohlen)**

Du legst ein neues Repo an mit dem Namen exakt `tfb74.github.io`:
```bash
git@github.com:tfb74/tfb74.github.io.git
```
Dort kommt nur die AASA-Datei rein:
```
tfb74.github.io/
└── .well-known/
    └── apple-app-site-association   (kein .json-Suffix!)
```

GitHub Pages serviert diesen Inhalt unter `https://tfb74.github.io/.well-known/apple-app-site-association`. Der Rest deines `SimpleTracker`-Repos bleibt unverändert.

**Option B — Custom Domain für SimpleTracker**

Wenn du eine eigene Domain hast (z. B. `simpletracking.de`), kannst du diese im SimpleTracker-Repo unter Settings → Pages → Custom domain hinterlegen. Dann wird `https://simpletracking.de/.well-known/...` möglich. In dem Fall musst du:
1. In den Entitlements `applinks:simpletracking.de` statt `tfb74.github.io` eintragen
2. URLs in der App entsprechend anpassen

**Option C — In den Setup-Files-Repo, falls schon vorhanden**

Falls du das Repo `tfb74.github.io` schon für andere Sachen nutzt, einfach die `.well-known/apple-app-site-association` dort committen.

## Was wo hin gehört

### Datei 1: AASA (zur Domain-Wurzel)

Quelldatei in diesem Repo:
```
AppStoreSubmission/universal-links/apple-app-site-association
```

Ziel auf GitHub Pages:
```
tfb74.github.io/.well-known/apple-app-site-association
```

**WICHTIG:**
- Datei-Name **exakt** `apple-app-site-association` (kein `.json`!)
- MIME-Type muss `application/json` sein (GitHub Pages macht das automatisch korrekt)
- Mit `curl -I` testen ob sie unter `Content-Type: application/json` ausgeliefert wird

### Datei 2: friend/index.html (in dein SimpleTracker-Repo)

Quelldatei in diesem Repo:
```
AppStoreSubmission/universal-links/friend/index.html
```

Ziel im SimpleTracker-Repo (auf main-Branch):
```
SimpleTracker/friend/index.html
```

GitHub Pages serviert das automatisch unter:
```
https://tfb74.github.io/SimpleTracker/friend?code=ABC-123
```

### Datei 3: friend/preview.png (du musst noch erstellen)

Für die Rich-Preview in iMessage brauchst du ein 1200×630px PNG/JPG, das im OG-Tag referenziert ist.

Inhalt z. B.:
- App-Logo
- Schriftzug „SimpleTracking"
- „Workout · Ernährung · Schritte" als Subtitle

Wo:
```
SimpleTracker/friend/preview.png
```

## Validation

Nach dem Hochladen testen:

```bash
# 1. AASA muss erreichbar sein und JSON sein
curl -I https://tfb74.github.io/.well-known/apple-app-site-association
# Content-Type sollte "application/json" sein
# Response 200

# 2. Apple's eigenes Diagnostics-Tool
# https://search.developer.apple.com/appsearch-validation-tool/
# → Domain: tfb74.github.io
# → Sollte "App association successful" zeigen

# 3. Landing-Page checken
curl https://tfb74.github.io/SimpleTracker/friend?code=TEST-123
# OG-Tags + Code-Anzeige sichtbar
```

## App-Store-ID nachpflegen

In `friend/index.html` steht zweimal `PLACEHOLDER_APP_STORE_ID`. Das ist bewusst so, weil du diese ID erst NACH dem ersten App-Store-Eintrag von Apple bekommst.

**Sobald die App in ASC angelegt ist:**
1. ASC → SimpleTracking → App Information → die numerische ID kopieren (z.B. `6543210987`)
2. Beide Vorkommen von `PLACEHOLDER_APP_STORE_ID` in `friend/index.html` ersetzen
3. Push → GitHub Pages updated automatisch

## Test-Flow auf dem iPhone

Nach Setup:
1. Im Safari auf dem iPhone: `https://tfb74.github.io/SimpleTracker/friend?code=ABC-123` öffnen
2. iOS sollte direkt die App öffnen statt die Webseite zu laden (=Universal Link funktioniert)
3. Falls iOS die Webseite öffnet: AASA noch nicht propagiert. iOS cacht aggressiv – manchmal hilft App löschen + neu installieren

## Aktuelle Konfiguration in der App

| | Wert |
|---|---|
| **Team ID** | `87G432SJNY` |
| **Bundle ID** | `de.baumannheim.SimpleTracking` |
| **App ID String** | `87G432SJNY.de.baumannheim.SimpleTracking` |
| **Associated Domain** | `applinks:tfb74.github.io` |
| **Akzeptierte Pfade** | `/friend`, `/SimpleTracker/friend`, jeweils + `?code=...` |
