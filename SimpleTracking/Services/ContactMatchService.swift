import Foundation
import Contacts

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#endif

/// Best-effort Matching von Friend-Namen mit den Kontakten des Users.
/// Wird benutzt um in der Friends-UI das Kontakt-Photo anzuzeigen statt
/// dem Avatar — sofern der User Contacts-Zugriff erteilt hat und der
/// Name eindeutig zugeordnet werden kann.
///
/// Privacy-Hinweis: wir lesen nur Name + Thumbnail, schicken nichts nach
/// außen. Die Matches werden in-memory gehalten (kein UserDefaults-Cache),
/// damit beim Widerruf der Berechtigung sofort nichts mehr da ist.
@Observable
@MainActor
final class ContactMatchService {
    static let shared = ContactMatchService()

    /// True wenn der User Contacts-Zugriff explizit erteilt hat.
    private(set) var authorizationStatus: CNAuthorizationStatus = .notDetermined

    /// Name → optionales Thumbnail. Lookup via lowercased name.
    private var photoCache: [String: PlatformImage] = [:]
    /// Name → CNContact (lazy). Für Detail-Sprünge ("In Kontakten öffnen").
    private var contactCache: [String: CNContact] = [:]

    private let store = CNContactStore()

    private init() {
        // Aktueller Auth-Status (synchron lesbar)
        authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
    }

    /// Fragt einmalig nach Berechtigung (idempotent). Wenn schon
    /// entschieden, kein Re-Prompt.
    func requestAccessIfNeeded() async {
        guard authorizationStatus == .notDetermined else { return }
        let granted = (try? await store.requestAccess(for: .contacts)) ?? false
        authorizationStatus = granted ? .authorized : .denied
    }

    /// Gibt ein Photo für den Friend-Namen zurück (falls Match möglich).
    /// Synchron — falls noch nicht geladen, fire-and-forget Background-Load.
    func photo(for friendName: String) -> PlatformImage? {
        let key = normalize(friendName)
        if let cached = photoCache[key] { return cached }
        // Async lookup im Hintergrund — UI ruft uns beim nächsten render erneut
        let snapshot = authorizationStatus
        if snapshot == .authorized {
            Task { @MainActor in
                await self.lookupAndCache(name: friendName)
            }
        }
        return nil
    }

    /// Manueller Bulk-Load. Wird beim Friends-Tab-Öffnen aufgerufen damit
    /// die Photos beim ersten Render schon da sind.
    func preloadPhotos(for names: [String]) async {
        guard authorizationStatus == .authorized else { return }
        for name in names {
            await lookupAndCache(name: name)
        }
    }

    private func lookupAndCache(name: String) async {
        let key = normalize(name)
        guard photoCache[key] == nil else { return }
        guard !key.isEmpty else { return }

        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey,
            CNContactFamilyNameKey,
            CNContactThumbnailImageDataKey
        ].map { $0 as CNKeyDescriptor }

        // Zuerst Vorname-Predicate (häufigster Fall: User hat nur Vornamen
        // als Profilname). Bei mehreren Treffern: bevorzuge exakt-match
        // von ganzem Namen.
        let predicate = CNContact.predicateForContacts(matchingName: name)
        let contacts = (try? store.unifiedContacts(matching: predicate, keysToFetch: keys)) ?? []

        let exact = contacts.first { c in
            let full = "\(c.givenName) \(c.familyName)".trimmingCharacters(in: .whitespaces)
            return normalize(full) == key || normalize(c.givenName) == key
        } ?? contacts.first

        if let c = exact {
            contactCache[key] = c
            if let data = c.thumbnailImageData, let img = PlatformImage(data: data) {
                photoCache[key] = img
            }
        }
    }

    private func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
         .lowercased()
         .folding(options: .diacriticInsensitive, locale: .current)
    }
}
