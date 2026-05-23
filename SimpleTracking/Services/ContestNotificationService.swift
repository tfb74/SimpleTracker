import Foundation
@preconcurrency import UserNotifications

/// Plant lokale Erinnerungen für Contests:
/// - 24h vor Deadline
/// - bei Daily Streak: täglich um 19:00 Uhr falls Tagesziel noch offen
///
/// MVP nutzt nur lokale Notifications (UNUserNotificationCenter), keine
/// Server-Push. Das deckt die meisten Anwendungsfälle ab und braucht keine
/// APNs-Infrastruktur.
@MainActor
final class ContestNotificationService {
    static let shared = ContestNotificationService()

    private init() {}

    /// Beim App-Start aufrufen — fragt Permission und plant alle relevanten
    /// Reminder neu (vorhandene mit gleicher ID werden überschrieben).
    func setup() async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return }

        // Alte Contest-Notifications entfernen, dann neu planen.
        // Async-Variante statt Completion-Closure → kein Sendable-Capture-Problem.
        let pending = await center.pendingNotificationRequests()
        let toRemove = pending.map(\.identifier).filter { $0.hasPrefix("contest_") }
        if !toRemove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: toRemove)
        }

        for contest in ContestService.shared.contests where contest.isActive && contest.endDate > Date() {
            scheduleReminders(for: contest)
        }
    }

    func scheduleReminders(for contest: Contest) {
        scheduleDeadlineReminder(for: contest)
        if contest.type == .dailyStreak {
            scheduleDailyTargetReminder(for: contest)
        }
    }

    func cancelReminders(for contest: Contest) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [
            "contest_deadline_\(contest.contestID)",
            "contest_daily_\(contest.contestID)"
        ])
    }

    // MARK: - Private

    private func scheduleDeadlineReminder(for contest: Contest) {
        // 24h vor Deadline
        let triggerDate = contest.endDate.addingTimeInterval(-24 * 3600)
        guard triggerDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = lt("Contest endet bald!")
        content.body = lf("\"%@\" endet morgen. Letzte Chance!", contest.title)
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate),
            repeats: false
        )
        let req = UNNotificationRequest(
            identifier: "contest_deadline_\(contest.contestID)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(req) { _ in }
    }

    private func scheduleDailyTargetReminder(for contest: Contest) {
        // Jeden Abend um 19:00 wenn Contest noch läuft
        let content = UNMutableNotificationContent()
        content.title = lt("Tagesziel checken")
        content.body = lf("Hast du heute dein Ziel für \"%@\" erreicht?", contest.title)
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = 19
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let req = UNNotificationRequest(
            identifier: "contest_daily_\(contest.contestID)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(req) { _ in }
    }
}
