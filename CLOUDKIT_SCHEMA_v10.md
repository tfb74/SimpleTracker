# CloudKit Schema – Stand Build 10

Container: **iCloud.de.baumannheim.SimpleTracking**
Database: **Public**, Zone: **_defaultZone**

## Neue Record Types & Felder (relative zu Build 9)

### `STMessage` *(NEU)*
Direkt-Nachrichten zwischen zwei Friends.

| Field | Type | Index |
|---|---|---|
| `reactionID` *(wiederverwendet als message-id)* | STRING | Queryable |
| `fromCode` | STRING | Queryable |
| `fromName` | STRING | — |
| `targetCode` *(Empfänger)* | STRING | **Queryable** |
| `text` | STRING | — |
| `timestamp` | DATE/TIME | Queryable + Sortable |
| `readAt` | DATE/TIME | — |

### Bestehende Types: keine Schema-Änderung
`STUserProfile`, `STActivity`, `STReaction`, `STFriendShareInvite` sind unverändert.

**Wichtig:** `STReaction` darf jetzt mehrere Records pro `(fromCode, activityID)`-Kombo haben — RecordName ist nicht mehr deterministisch. Schema-Constraint bleibt aber gleich.

## Subscriptions (werden automatisch von der App angelegt)

| Subscription-ID | Filter | Push-Trigger |
|---|---|---|
| `sub.friendActivity` | `STActivity WHERE code IN <my friends>` | Push wenn Freund neue Activity postet |
| `sub.reactionsOnMine` | `STReaction WHERE fromCode != myCode` | Push wenn jemand reagiert (client-seitig nach myActivityID gefiltert) |
| `sub.messagesToMe` | `STMessage WHERE targetCode == myCode` | Push wenn jemand DM schickt |

## Security Roles

`_icloud`: **Create + Read + Write** auf alle 5 Types (STUserProfile, STActivity, STReaction, STFriendShareInvite, **STMessage**).

## Deployment-Checkliste

1. CloudKit Dashboard → **Development** → Record Types → `+`
2. **STMessage** anlegen mit Feldern oben
3. Indexes setzen (siehe Tabelle)
4. Security Roles → `_icloud` → Read/Create/Write auf STMessage ankreuzen → Save
5. **Deploy Schema Changes** → Production

Erst danach funktionieren Direktnachrichten im Production-Build.
