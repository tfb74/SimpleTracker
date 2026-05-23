# Contests – Implementiert (Phase 3)

> Status: **Implementiert** als vollständiger MVP inklusive Teams, Sub-Teams und lokalen Notifications. Erreichbar unter „Mehr → Contests" sowie „Mehr → Teams".

## Kernidee

User erstellt einen befristeten **Wettbewerb** mit messbarem Ziel (z. B. „10.000 Schritte täglich" oder „im Mai 100 km laufen") und lädt andere ein. Während der Laufzeit wird der Fortschritt aller Teilnehmer in einem **Leaderboard** und einem **Dashboard** sichtbar.

Drei Skalen, mit demselben Mechanismus:
1. **Friends-Contest** (2–10 Personen, Code-basiert wie Friends)
2. **Team-Contest** (10–50, fester Teilnehmerkreis, eigener Team-Code)
3. **Firma mit Sub-Teams** (50+, hierarchisch — z. B. „Zalaris Vertrieb" als Sub-Team von „Zalaris")

Ziel: gleiche Daten-Pipeline für alle drei Skalen, nur die UI und der Hierarchie-Layer unterscheiden sich.

---

## Wettbewerbs-Typen (MVP-Scope)

| Typ | Metrik | Beispiel |
|---|---|---|
| **Daily Streak** | tägliche Schwelle | „Jeden Tag 10.000 Schritte" |
| **Cumulative Total** | Gesamtsumme bis Deadline | „Im Mai zusammen 100 km laufen" |
| **Score Race** | höchster SimpleTracking-Score | „Wer schafft den höchsten Workout-Score?" |
| **Calorie Goal** | aktive Kalorien | „Diese Woche 3.500 kcal verbrennen" |

Alle vier basieren auf existierenden Datenquellen (HealthKit, WorkoutRecords, FoodLog), keine neue Sensorik nötig.

**Nicht im MVP:**
- Kreuzwettbewerbe zwischen Sportarten
- Live-Wettkämpfe „first to finish"
- Wettbewerbe mit echtem Geld
- Trash-Talk-Chat (zu komplex, später als Phase 2 möglich)

---

## Datenmodell (CloudKit Public Database)

Erweitern wir den bestehenden CloudKit-Stack mit drei neuen Record Types:

### STContest

| Feld | Typ | Indexed | Beschreibung |
|---|---|---|---|
| `contestID` | String | queryable | UUID, public Key |
| `ownerCode` | String | queryable | Friend-Code des Erstellers |
| `title` | String | – | „Mai-Schritt-Challenge" |
| `description` | String? | – | optionaler Erklärungstext |
| `type` | String | – | enum: daily_streak, total, score, calories |
| `metric` | String | – | steps, distance, calories, score |
| `targetValue` | Double | – | Schwelle (10000) oder Gesamt-Ziel (100000) |
| `startDate` | Date | sortable | wann läuft's los |
| `endDate` | Date | sortable | Deadline |
| `scope` | String | – | friends, team, company |
| `teamID` | String? | queryable | bei Team/Company-Scope: FK zu STTeam |
| `inviteCode` | String | queryable | 8-stellig, zum Beitreten |
| `isActive` | Bool | – | wird nach Ende auf false gesetzt |

### STContestParticipant

| Feld | Typ | Indexed | Beschreibung |
|---|---|---|---|
| `participantID` | String | – | UUID |
| `contestID` | String | queryable | FK zu STContest |
| `userCode` | String | queryable | Friend-Code des Teilnehmers |
| `displayName` | String | – | Anzeigename (denormalisiert) |
| `avatarPreset` | String | – | für UI-Anzeige |
| `joinedAt` | Date | – | wann beigetreten |
| `subTeamID` | String? | – | bei Firma mit Sub-Teams |

### STContestProgress

Eine Datei pro Teilnehmer pro Tag — ermöglicht Verlaufs-Charts.

| Feld | Typ | Indexed | Beschreibung |
|---|---|---|---|
| `progressID` | String | – | UUID |
| `contestID` | String | queryable | FK |
| `userCode` | String | queryable | FK |
| `date` | Date | sortable | Tag |
| `value` | Double | – | für diesen Tag erreichter Wert |
| `cumulativeValue` | Double | – | Gesamtwert bis Tag X (für „Total"-Typen) |
| `dailyTargetMet` | Bool | – | für „Daily Streak" — Tagesziel erreicht? |

### STTeam (für Team/Company-Scope)

| Feld | Typ | Indexed | Beschreibung |
|---|---|---|---|
| `teamID` | String | queryable | UUID |
| `parentTeamID` | String? | queryable | für Sub-Teams (= Firma → Abteilung) |
| `name` | String | – | „Zalaris" oder „Zalaris Vertrieb" |
| `inviteCode` | String | queryable | um Team beizutreten |
| `ownerCode` | String | queryable | Code des Team-Admins |
| `memberCount` | Int | – | denormalisiert für Dashboard-Performance |

---

## User Flows

### A) Contest erstellen

1. Tab „Mehr" → „Contests" → **„+ Neuer Contest"**
2. Sheet:
   - Titel + optionale Beschreibung
   - Typ wählen (4 Auswahlmöglichkeiten mit Erklärung)
   - Ziel-Wert eintippen (Schwelle oder Gesamt)
   - Start- und End-Datum
   - Scope: **Freunde-Code** / **Team beitreten** / **Neues Team gründen**
3. „Erstellen" → CloudKit speichert STContest, generiert Invite-Code
4. Share-Sheet automatisch mit Invite-Link (`simpletracking://contest?code=XXXX`) und QR-Code

### B) Contest beitreten

1. Freund schickt Invite-Link → tap → App öffnet
2. Sheet: „Felix lädt dich ein zu **Mai-Schritt-Challenge** — 10.000 Schritte täglich bis 31. Mai. Mitmachen?"
3. „Beitreten" → STContestParticipant wird angelegt
4. Erscheint im Contest-Tab mit Live-Progress

### C) Während der Laufzeit

- App tracked automatisch HealthKit-Werte und schreibt täglich Mitternachts (oder beim App-Start) ein STContestProgress-Record
- Dashboard zeigt aktuellen Stand
- Bei wichtigen Meilensteinen: optionale Push-Benachrichtigung („Du liegst auf Platz 1!" / „Tom hat dich überholt!")

### D) Contest beendet

- App markiert isActive = false
- Notification an alle Teilnehmer mit Endergebnis
- Sieger-Confetti-Animation für Top 3
- Contest bleibt im Verlauf einsehbar

---

## UI – Drei Hauptbereiche

### 1. Contest-Liste (neuer Reiter / Sektion in „Mehr")
- **Aktive Contests** mit Live-Progress-Balken
- **Zukünftige** (warten auf Start)
- **Beendete** mit Endergebnis
- „+ Neuer Contest" Button oben rechts

### 2. Contest-Detail (Dashboard)
Wenn ein Contest angetippt wird:
- Header: Titel, Restzeit, Ziel
- Eigener Fortschritt prominent (Ring-Chart)
- **Leaderboard** sortiert nach Fortschritt:
  - Bei Daily Streak: Anzahl erreichter Tage
  - Bei Total: aktuelle Summe
  - Bei Score Race: höchster Score
  - Bei Calorie Goal: kumulierte Kalorien
- Avatar + Name + Wert + Position-Wechsel-Indikator (↑↓)
- Bei Sub-Team-Scope: zwei Tabs „Mein Team" und „Gesamt"

### 3. Trends / Charts (innerhalb Detail)
- Line-Chart: eigener Fortschritt vs. Gruppen-Durchschnitt
- Bar-Chart: Tagesbeste
- Bei Team-Contests: Sub-Team-Vergleich als gestapeltes Bar-Chart

---

## Hierarchie für Firma + Sub-Teams

Damit das nicht in „Enterprise-Software" abdriftet, halten wir's flach:

```
STTeam "Zalaris" (parentTeamID = nil)
├── STTeam "Zalaris Vertrieb" (parentTeamID = "Zalaris")
├── STTeam "Zalaris Engineering" (parentTeamID = "Zalaris")
└── STTeam "Zalaris HR" (parentTeamID = "Zalaris")
```

- Maximal **2 Ebenen** (Firma → Sub-Team) — keine Sub-Sub-Teams
- Ein User kann in mehreren Sub-Teams sein
- Beim Contest-Beitritt wählt User sein Sub-Team aus, falls die Firma welche hat
- Leaderboard kann nach Sub-Team gefiltert oder aggregiert angezeigt werden

**Team-Admin** (= Ersteller des Teams):
- Kann Sub-Teams anlegen
- Kann User aus Team entfernen
- Kann Team-Name ändern

---

## Daten-Pipeline: Wie Progress synchronisiert wird

**Lokales Tracking:**
- Bei jedem App-Start prüft `ContestProgressService` alle aktiven Contests
- Holt vom HealthKit den Wert für `metric` × `Tag` × `userCode`
- Schreibt STContestProgress wenn neu / aktualisiert wenn geändert

**Cloud-Sync:**
- Andere Teilnehmer sehen das beim nächsten Pull-to-Refresh oder Contest-Detail-Öffnen
- Optional: stille CloudKit-Subscription für Live-Updates (advanced, nicht MVP)

**Privacy:**
- Nur teilnehmende User sehen Progress-Records des Contests
- Keine globale Aggregation über CloudKit Public DB
- Aktive Kalorien / Schritte sind sowieso schon in HealthKit; keine zusätzliche Sensorik

---

## Game Center Integration

- Spezielle Achievements wie „10 Contests gewonnen", „Erstes Team gegründet" etc.
- Keine direkte Punkte-Übertragung in GC-Leaderboards (das wäre Spam für andere User)

---

## Push-Benachrichtigungen (optional, nach MVP)

- Beitrittsanfragen
- Tagesziel verpasst (Daily Streak)
- Überholt worden (Leaderboard-Position-Wechsel)
- Contest endet in 24h
- Endergebnis bei Contest-Ende

Erfordert APNs-Setup und User-Permission für Push-Notifications.

---

## Implementierungs-Aufwand

Grobe Schätzung (für lean MVP, ohne Push):

| Komponente | LOC | Aufwand |
|---|---|---|
| Datenmodelle (Swift Codable) | 200 | klein |
| ContestService (CloudKit-CRUD) | 600 | mittel |
| ContestProgressService (Health-Sync) | 300 | mittel |
| ContestListView | 250 | klein |
| ContestDetailView (Dashboard) | 500 | mittel |
| ContestCreateSheet | 350 | klein |
| ContestJoinSheet | 200 | klein |
| TeamManagementView (für Firma-Admins) | 400 | mittel |
| Charts (Swift Charts) | 250 | klein |
| Übersetzungen (5 Sprachen × ~80 neue Keys) | 400 Zeilen | mittel |
| CloudKit-Schema-Setup (Dashboard manuell) | – | 30 min User |

**Geschätzt: ~3.500 LOC, 2-3 Tage konzentrierter Implementierungs-Aufwand.**

---

## Phasen-Vorschlag

**Phase 1 (MVP):**
- Friends-Scope
- 2 Contest-Typen: Daily Streak + Cumulative Total
- Einfaches Leaderboard
- Manuelle Pull-to-Refresh

**Phase 2 (Erweiterung):**
- Team-Scope mit Invite-Codes
- 4 Contest-Typen alle aktiv
- Charts und Trends
- Push-Benachrichtigungen

**Phase 3 (Enterprise):**
- Firma → Sub-Teams Hierarchie
- Admin-Verwaltung
- Aggregierte Dashboards
- Optional: Web-Dashboard für Firmen-Admins (separates Projekt)

---

## Offene Fragen für dich

1. **Wollen wir alle 4 Contest-Typen im MVP, oder erstmal nur Daily Streak + Total?**
2. **Wollen wir gleich Team-Scope einbauen, oder im MVP nur Friends?**
3. **Push-Benachrichtigungen für MVP wichtig oder Phase 2?**
4. **Sub-Teams für Firmen jetzt oder Phase 3?**
5. **Soll der Contest-Tab ein eigener Hauptreiter sein oder unter „Mehr"?**
6. **Auch Custom Sportarten (eigene Workout-Typen) als Contest-Metrik zulassen?**
7. **Wer darf Contests in einem Team starten — nur Admin oder jeder?**

Sag Bescheid wie du das siehst, dann passe ich den Plan an und können loslegen.
