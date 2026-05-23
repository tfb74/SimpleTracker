import Foundation

@Observable
final class FoodLogStore {
    static let shared = FoodLogStore()

    private(set) var entries: [FoodEntry] = []

    /// True wenn `load()` erfolgreich war ODER das File noch gar nicht existierte
    /// (Erstinstallation). False bedeutet: File ist da, konnte aber nicht
    /// dekodiert werden — in diesem Fall verweigert `save()` jeden Schreibzugriff,
    /// damit die unleserliche, aber möglicherweise reparierbare Original-Datei
    /// nicht überschrieben wird. Sichtbar nach außen für Diagnose-UI.
    private(set) var loadSucceeded = false
    private(set) var loadErrorMessage: String?

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("food_log.json")
    }()

    private var backupURL: URL {
        fileURL.deletingPathExtension().appendingPathExtension("backup.json")
    }

    private var corruptURL: URL {
        let stamp = Int(Date().timeIntervalSince1970)
        return fileURL.deletingPathExtension().appendingPathExtension("corrupt-\(stamp).json")
    }

    private init() { load() }

    // MARK: - Queries

    func entries(on date: Date) -> [FoodEntry] {
        let cal = Calendar.current
        return entries
            .filter { cal.isDate($0.timestamp, inSameDayAs: date) }
            .sorted { $0.timestamp > $1.timestamp }
    }

    func totals(on date: Date) -> (kcal: Double, carbs: Double, be: Double) {
        let es = entries(on: date)
        let kcal  = es.reduce(0.0) { $0 + $1.resolvedCalories }
        let carbs = es.reduce(0.0) { $0 + $1.resolvedCarbsGrams }
        return (kcal, carbs, FoodEntry.breadUnits(fromCarbs: carbs))
    }

    // MARK: - Mutation
    //
    // Alle Mutationen schreiben parallel nach Apple Health, damit andere
    // Apps (Health, Waagen-Apps, Kalorienrechner usw.) die gleiche Sicht
    // auf Ernährung haben wie diese App. Die Health-Writes laufen
    // fire-and-forget im Hintergrund — lokale UI reagiert sofort.

    func add(_ entry: FoodEntry) {
        entries.append(entry)
        save()
        Task { [entry] in
            let ids = await HealthKitService.shared.writeFoodSamples(for: entry)
            await MainActor.run {
                if !ids.isEmpty, let i = self.entries.firstIndex(where: { $0.id == entry.id }) {
                    self.entries[i].healthKitSampleIDs = ids
                    self.save()
                }
            }
            // Optionaler Friend-Share: nur wenn User für diesen Eintrag
            // explizit „mit Freunden teilen" aktiviert hat.
            await CloudKitService.shared.publishMealIfShared(entry)
        }
    }

    func update(_ entry: FoodEntry) {
        guard let i = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        let old = entries[i]
        entries[i] = entry
        save()
        // Einfacher Ansatz: alte Samples löschen, neue schreiben.
        Task { [old, entry] in
            await HealthKitService.shared.deleteFoodSamples(uuids: old.healthKitSampleIDs ?? [])
            let ids = await HealthKitService.shared.writeFoodSamples(for: entry)
            await MainActor.run {
                if let j = self.entries.firstIndex(where: { $0.id == entry.id }) {
                    self.entries[j].healthKitSampleIDs = ids
                    self.save()
                }
            }
            // Share-Sync:
            // - vorher geteilt, jetzt nicht mehr → unpublish
            // - vorher nicht geteilt, jetzt schon → publish
            // - beide gleich → republish (Daten haben sich geändert)
            let wasShared = old.sharedWithFriends == true
            let isShared = entry.sharedWithFriends == true
            if wasShared && !isShared {
                await CloudKitService.shared.unpublishMeal(old)
            } else if isShared {
                await CloudKitService.shared.publishMealIfShared(entry)
            }
        }
    }

    func remove(_ entry: FoodEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
        Task { [entry] in
            await HealthKitService.shared.deleteFoodSamples(uuids: entry.healthKitSampleIDs ?? [])
            // Falls geteilt: aus Freunds-Feed entfernen
            if entry.sharedWithFriends == true {
                await CloudKitService.shared.unpublishMeal(entry)
            }
        }
    }

    func removeAll() {
        let snapshot = entries
        entries.removeAll()
        save()
        Task { [snapshot] in
            for e in snapshot {
                await HealthKitService.shared.deleteFoodSamples(uuids: e.healthKitSampleIDs ?? [])
            }
        }
    }

    // MARK: - Persistence

    /// Robuster Loader mit dreistufiger Recovery-Kaskade:
    /// 1. Versuche `food_log.json` zu dekodieren
    /// 2. Wenn das fehlschlägt: versuche `food_log.backup.json`
    /// 3. Wenn auch das fehlschlägt: kopiere kaputtes File nach
    ///    `food_log.corrupt-<timestamp>.json` damit es manuell repariert werden
    ///    kann, behalte aber im Speicher leeres Array — `save()` wird durch
    ///    `loadSucceeded = false` blockiert, damit die kaputte Original-Datei
    ///    nicht verloren geht.
    private func load() {
        // Fall A: kein File vorhanden → Erstinstallation → leeres Array ist OK
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            loadSucceeded = true
            return
        }

        // Fall B: File da → versuche zu dekodieren
        if let data = try? Data(contentsOf: fileURL),
           let decoded = decodeEntries(data) {
            entries = decoded
            loadSucceeded = true
            // Erfolgreicher Load → aktualisiere Backup
            try? data.write(to: backupURL, options: .atomic)
            return
        }

        // Fall C: Main file kaputt → versuche Backup
        if FileManager.default.fileExists(atPath: backupURL.path),
           let backupData = try? Data(contentsOf: backupURL),
           let decoded = decodeEntries(backupData) {
            entries = decoded
            loadSucceeded = true
            loadErrorMessage = "Hauptdatei beschädigt — aus Backup wiederhergestellt."
            print("[FoodLog] ⚠️ recovered from backup (\(decoded.count) entries)")
            // Backup hat funktioniert → kaputte Hauptdatei sicherheitshalber wegsichern
            try? FileManager.default.moveItem(at: fileURL, to: corruptURL)
            // Schreibe das Backup zurück als neue Hauptdatei
            try? backupData.write(to: fileURL, options: .atomic)
            return
        }

        // Fall D: weder File noch Backup brauchbar → bleibe im Read-Only-Modus
        loadSucceeded = false
        loadErrorMessage = "Ernährungs-Daten konnten nicht gelesen werden. Speichern ist gesperrt, damit keine weiteren Daten verloren gehen."
        // Sichere kaputte Datei für spätere Analyse, lasse Backup aber stehen
        if let data = try? Data(contentsOf: fileURL) {
            try? data.write(to: corruptURL, options: .atomic)
            print("[FoodLog] ❌ load failed — corrupt copy saved at \(corruptURL.lastPathComponent)")
        }
    }

    /// Dekodieren mit Forward-Compatibility-Toleranz: einzelne kaputte
    /// Einträge werden übersprungen statt das ganze Array zu verwerfen.
    private func decodeEntries(_ data: Data) -> [FoodEntry]? {
        // Strict-Decode versuchen
        if let decoded = try? JSONDecoder().decode([FoodEntry].self, from: data) {
            return decoded
        }
        // Fallback: jeden Eintrag einzeln versuchen (eintrag-für-eintrag tolerant)
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        var rescued: [FoodEntry] = []
        var skipped = 0
        for obj in jsonArray {
            if let entryData = try? JSONSerialization.data(withJSONObject: obj),
               let entry = try? JSONDecoder().decode(FoodEntry.self, from: entryData) {
                rescued.append(entry)
            } else {
                skipped += 1
            }
        }
        if skipped > 0 {
            print("[FoodLog] partial decode: \(rescued.count) ok, \(skipped) skipped")
        }
        // Nur als „erfolgreich" gelten lassen wenn die Mehrheit dekodiert wurde,
        // sonst sieht's eher nach Format-Wechsel aus → Backup-Pfad bevorzugen
        return rescued.count >= max(1, jsonArray.count - jsonArray.count / 3) ? rescued : nil
    }

    private func save() {
        // KRITISCH: Wenn der initiale Load gescheitert ist (kaputtes File mit
        // möglicherweise wichtigen Daten), darf save() NICHT die kaputte Datei
        // überschreiben — sonst sind die Original-Daten endgültig weg. Erst
        // wenn der User die Recovery durchgeführt hat (oder bestätigt dass
        // er bei Null anfängt), wird wieder geschrieben.
        guard loadSucceeded else {
            print("[FoodLog] ❌ save blocked — initial load failed, preserving original file")
            return
        }

        guard let data = try? JSONEncoder().encode(entries) else { return }

        // Atomisches Backup-Rotation: erst Backup aktualisieren, dann Main
        // überschreiben. Im Fehlerfall haben wir immer mindestens den vorigen
        // gültigen Stand verfügbar.
        if let oldData = try? Data(contentsOf: fileURL) {
            try? oldData.write(to: backupURL, options: .atomic)
        }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Recovery

    /// Manueller Reset nach Datenverlust — wird vom UI aufgerufen wenn der
    /// User bestätigt, dass er die kaputte Datei wegwerfen will. Entriegelt
    /// save() wieder, sodass neue Einträge persistiert werden.
    func acceptDataLossAndContinue() {
        guard !loadSucceeded else { return }
        loadSucceeded = true
        loadErrorMessage = nil
        entries.removeAll()
        // Schreibe leeres Array als sauberen Neustart
        if let data = try? JSONEncoder().encode([FoodEntry]()) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Rekonstruktion aus Apple Health: liest alle dietary-Samples die wir
    /// jemals geschrieben haben (sourceBundleIdentifier == app bundle) und
    /// baut daraus FoodEntries. Wird vom UI über „Aus Apple Health
    /// wiederherstellen"-Button getriggert.
    func recoverFromHealthKit() async -> Int {
        let recovered = await HealthKitService.shared.fetchOwnFoodEntries()
        await MainActor.run {
            // Mergen statt überschreiben: bestehende Einträge (per ID) bleiben,
            // neue aus HealthKit dazu, Duplikate (gleiche timestamp + name)
            // werden gefiltert.
            var byKey: [String: FoodEntry] = [:]
            for e in self.entries {
                byKey[Self.dedupeKey(for: e)] = e
            }
            for e in recovered {
                let k = Self.dedupeKey(for: e)
                if byKey[k] == nil {
                    byKey[k] = e
                }
            }
            self.entries = Array(byKey.values).sorted { $0.timestamp > $1.timestamp }
            self.loadSucceeded = true
            self.loadErrorMessage = nil
            self.save()
        }
        return recovered.count
    }

    private static func dedupeKey(for entry: FoodEntry) -> String {
        // Gleiche Mahlzeit ≈ gleicher Name + gleiche Minute
        let minute = Int(entry.timestamp.timeIntervalSince1970 / 60)
        return "\(entry.name.lowercased())|\(minute)"
    }
}
