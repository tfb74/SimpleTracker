# Community Feature – Konzept

## Ziel

Friends-Feed und Code-Austausch, **schlank**, ohne eigenes Backend, mit voller Kontrolle über Privatsphäre.

## Nicht-Ziele

- Direktnachrichten
- Likes / Kommentare (kommt evtl. später)
- Push-Benachrichtigungen für neue Feed-Items
- Discovery (User können sich nicht "browsen", nur über Code finden)
- Foto-Uploads

## Architektur

**CloudKit Public Database** – kostenlos, Apple-nativ, kein Backend-Ops.

```
┌─────────────────────┐       ┌──────────────────┐
│  iPhone A           │       │  iPhone B        │
│  Felix              │       │  Anna            │
│  Code: ABC-123      │       │  Code: XYZ-789   │
└──────────┬──────────┘       └────────┬─────────┘
           │ schreibt              schreibt│
           ▼                              ▼
    ┌──────────────────────────────────────┐
    │  CloudKit Public Database            │
    │  ┌────────────────┐ ┌──────────────┐ │
    │  │ STUserProfile  │ │ STActivity   │ │
    │  │ - code         │ │ - code       │ │
    │  │ - displayName  │ │ - eventType  │ │
    │  │ - avatarPreset │ │ - eventTitle │ │
    │  │ - lastSeen     │ │ - timestamp  │ │
    │  └────────────────┘ └──────────────┘ │
    └──────────────────────────────────────┘
           │ liest                          │
           ▼                              ▼
    Feed = alle STActivity wo code ∈ {meine Freunde}
```

## Datenmodell

### STUserProfile (Public DB)
| Feld | Typ | Indexed | Beschreibung |
|---|---|---|---|
| `code` | String | queryable | 6-stelliger Friend-Code (XXX-YYY) – Primary Key |
| `displayName` | String | – | Anzeigename des Users |
| `avatarPreset` | String | – | Avatar-Symbol-Auswahl |
| `lastSeen` | Date | – | letzter App-Start (für Sichtbarkeit) |

### STActivity (Public DB)
| Feld | Typ | Indexed | Beschreibung |
|---|---|---|---|
| `id` | String | – | UUID, eindeutig pro Activity |
| `code` | String | queryable | Code des Erstellers |
| `eventType` | String | – | "workout" oder "achievement" |
| `eventTitle` | String | – | z.B. „5km Lauf" |
| `eventDetail` | String | – | z.B. „32:14 min · 380 kcal" |
| `workoutTypeRaw` | String? | – | optional, für Icon-Mapping |
| `timestamp` | Date | sortable | wann passiert |

### STReaction (Public DB)

Eine kurze Reaktion („Anfeuerung") auf eine Aktivität. 1 Reaktion pro User pro Activity.

| Feld | Typ | Indexed | Beschreibung |
|---|---|---|---|
| `reactionID` | String | – | UUID der Reaktion (= `fromCode_activityID`) |
| `activityID` | String | queryable | FK zu `STActivity.activityID` |
| `fromCode` | String | – | Code des Reaktions-Senders |
| `fromName` | String | – | Anzeigename (denormalisiert für Offline-View) |
| `emoji` | String | – | 👍 ❤️ 🔥 💪 🎉 |
| `text` | String? | – | optionaler Kommentar, max 80 Zeichen |
| `timestamp` | Date | sortable | wann gesendet |

## Privatsphäre

- Public Database = alle Records prinzipiell lesbar von jedem iCloud-User
- ABER: Queries nur über bekannte Freund-Codes → keine Browsability
- Code ist 6-stellig zufällig, ohne Username = effektiv anonym
- Codes haben 32^6 = ~1 Mrd. Möglichkeiten → bruteforce-resistent
- User können eigene Aktivitäten jederzeit aus dem Feed löschen
- iCloud-Account ist Voraussetzung – fällt der weg, ist Community nicht verfügbar (App funktioniert weiter)

## User Flows

### A) Erstes Mal
1. App-Start → CloudKit-Setup wenn iCloud verfügbar
2. Eigenes `STUserProfile` mit Code wird in Public DB registriert
3. UI zeigt eigenen Code prominent + „Code teilen"-Button

### B) Freund hinzufügen via Code
1. Tap auf „+" Icon
2. Code eintippen (oder QR scannen – v2)
3. Lookup per `STUserProfile`-Query nach `code`
4. Wenn gefunden: Profil-Daten lokal ablegen + `displayName` + `avatarPreset` cachen
5. Code wird zur lokalen Friend-Liste hinzugefügt (UserDefaults)

### C) Code mit Freunden teilen
1. Tap auf „Code teilen"
2. iOS Share Sheet → Messages, AirDrop, etc. mit Vorschau-Text:
   > „Folge mir in SimpleTracking. Mein Code: **ABC-123**"
3. Optional: QR-Code anzeigen → Freund scannt mit Kamera

### D) Workout abgeschlossen
1. `HealthKitService.saveWorkout()` → fertig
2. CloudKitService publishWorkoutIfNeeded() schreibt `STActivity` in Public DB
3. Bei Freunden bei nächstem Refresh sichtbar

### E) Feed laden
1. FriendsView öffnen → `cloudKit.refreshFeed()`
2. Query: alle `STActivity` wo `code IN [meine-Freund-Codes]`, letzte 14 Tage, sortiert nach `timestamp DESC`
3. Lokal speichern, UI updaten
4. Pull-to-Refresh ruft erneut auf

## Implementierung – Reihenfolge

1. **CloudKit Capability** in Entitlements + iCloud Container ID
2. **CloudKitService** – ersetzt den Stub
3. **QR-Code** für eigenen Code (Sender-Seite)
4. **FriendsView** – Coming-Soon-Banner kontextabhängig (zeigt nur wenn `iCloudUnavailable`, sonst echte Daten)
5. **CloudKit Dashboard** – Schema-Deployment (manuell durch User)

## Setup-Schritte (manuell, durch User)

Nach Deploy:
1. Xcode → SimpleTracking Target → Signing & Capabilities → **+ iCloud**
   - CloudKit aktivieren
   - Container `iCloud.de.baumannheim.SimpleTracking` auswählen oder erstellen
2. App auf iPhone bauen + einmal starten → Records werden in **Development** Environment angelegt
3. Manuell in **CloudKit Dashboard** (https://icloud.developer.apple.com):
   - Container → Schema → Indexes setzen:
     - `STUserProfile.code` → **QUERYABLE**
     - `STActivity.code` → **QUERYABLE**
     - `STActivity.timestamp` → **SORTABLE**
     - `STReaction.activityID` → **QUERYABLE**
     - `STReaction.timestamp` → **SORTABLE**
4. Vor App-Store-Submission: **Deploy Schema** von Development zu Production
