import Foundation
import UserNotifications

enum NotificationScheduler {
    private static let checkInIdentifier = "shipped.daily-checkin"
    private static let nudgeIdentifier = "shipped.behind-nudge"
    static let authorizedKey = "notificationsAuthorized"

    /// Recorded so the app can say plainly that the daily check-in won't arrive. Silently
    /// behaving as if it were scheduled meant the whole accountability loop could be off
    /// without the user ever being told.
    static var isAuthorized: Bool {
        get { AppSettings.defaults.bool(forKey: authorizedKey) }
        set { AppSettings.defaults.set(newValue, forKey: authorizedKey) }
    }

    /// Re-reads the real system state, which can change in Settings at any time.
    @discardableResult
    static func refreshAuthorization() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let granted = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
        isAuthorized = granted
        return granted
    }

    /// Asks for permission. Called at the commit step in onboarding — the one moment the
    /// user actively wants to be interrupted later.
    @discardableResult
    static func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            return granted
        } catch {
            isAuthorized = false
            return false
        }
    }

    /// Replaces any existing check-in with a daily repeat at the given hour.
    static func scheduleDailyCheckIn(at hour: Int, goalTitle: String) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [checkInIdentifier])

        let content = UNMutableNotificationContent()
        content.title = "What did you do today?"
        content.body = goalTitle
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(
            identifier: checkInIdentifier,
            content: content,
            trigger: trigger
        )

        try? await center.add(request)
    }

    /// A harder nudge the morning after a miss. Separate from the daily check-in so it can
    /// be cleared the moment the user catches up.
    static func scheduleBehindNudge(missedDays: Int, goalTitle: String) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [nudgeIdentifier])
        guard missedDays > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = missedDays == 1 ? "You missed a day" : "You've missed \(missedDays) days"
        content.body = "\(goalTitle) — open Shipped and decide what it costs."
        content.sound = .default

        var components = DateComponents()
        components.hour = 9
        components.minute = 0

        let request = UNNotificationRequest(
            identifier: nudgeIdentifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        )
        try? await center.add(request)
    }

    static func cancelBehindNudge() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [nudgeIdentifier])
    }

    static func cancelDailyCheckIn() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [checkInIdentifier])
    }
}
