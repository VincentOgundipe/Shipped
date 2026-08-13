import Foundation
import SwiftData

/// How much the user can realistically give per day. Without this the generated plan
/// is calibrated to nobody and gets abandoned in the first week.
enum Capacity: String, Codable, CaseIterable, Identifiable {
    case light
    case steady
    case allIn

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: return "30 min a day"
        case .steady: return "A couple hours"
        case .allIn: return "All in"
        }
    }

    var blurb: String {
        switch self {
        case .light: return "One small thing, most days."
        case .steady: return "Real work, around a job."
        case .allIn: return "This is the priority."
        }
    }

    /// Handed to Claude so task size matches the time available.
    var promptDescription: String {
        switch self {
        case .light: return "about 30 minutes per day — keep each task small enough to finish in one sitting"
        case .steady: return "about 2 hours per day — tasks can involve real depth but must fit one evening"
        case .allIn: return "a full working day, 6+ hours — tasks can be substantial multi-part pushes"
        }
    }
}

@Model
final class Goal {
    var title: String
    var deadline: Date
    var createdAt: Date

    /// The deadline the user first committed to. Kept so a pushed deadline can be
    /// shown honestly as slippage instead of quietly rewriting history.
    var originalDeadline: Date

    var capacityRaw: String
    /// Hour of day (0–23) for the daily check-in nudge.
    var checkInHour: Int
    /// How many times the plan has been recut after falling behind.
    var recutCount: Int

    /// Finished or retired goals stay in the store for history but drop out of every query,
    /// so starting a new goal can no longer silently hide the old one.
    var isArchived: Bool = false
    var completedAt: Date?

    /// Days the user explicitly excused. A streak survives these; missed work still moves.
    var restDays: [Date] = []

    /// The plan as it was immediately before the last recut, so a bad recut is undoable.
    var planSnapshot: Data?

    /// Stable across devices, unlike SwiftData's own `persistentModelID`. Sync uses this to
    /// recognise "the same goal" between the phone and the Mac's separate local stores.
    ///
    /// Optional and undefaulted on purpose — see `resolvedSyncID`. A CoreData/SwiftData
    /// lightweight migration can only add a column whose default is one fixed value for
    /// every existing row; `UUID()` is a different value per row, which isn't lightweight-
    /// migratable, and silently wiped an existing store rather than erroring the first time
    /// this shipped as a non-optional stored default. Nil-by-default (a plain NULL column)
    /// is always migration-safe.
    var syncID: UUID?
    /// Bumped on every local change; sync compares this to decide which side is newer.
    var updatedAt: Date?
    /// True while this row still needs to be pushed. Nil is treated as "needs sync" — see
    /// `needsSync` — so a goal from before this field existed gets pushed once, not ignored.
    var pendingSync: Bool?

    @Relationship(deleteRule: .cascade, inverse: \DailyTask.goal)
    var tasks: [DailyTask] = []

    init(
        title: String,
        deadline: Date,
        createdAt: Date = .now,
        capacity: Capacity = .steady,
        checkInHour: Int = 20
    ) {
        self.title = title
        self.deadline = deadline
        self.createdAt = createdAt
        self.originalDeadline = deadline
        self.capacityRaw = capacity.rawValue
        self.checkInHour = checkInHour
        self.recutCount = 0
        // Plain assignment in code, not a schema-level default — safe either way, but this
        // is also just normal ergonomics: a goal created today should have an id today.
        self.syncID = UUID()
        self.updatedAt = createdAt
        self.pendingSync = true
    }

    /// The real, stable identity to sync with — generating and caching one on first use for
    /// any row that predates this field (which is the whole point of it being optional).
    var resolvedSyncID: UUID {
        if let syncID { return syncID }
        let generated = UUID()
        syncID = generated
        return generated
    }

    var resolvedUpdatedAt: Date { updatedAt ?? createdAt }
    var needsSync: Bool { pendingSync ?? true }

    /// Call after any local mutation so sync knows this row changed and is newer than
    /// whatever's on the server.
    func markDirty() {
        updatedAt = .now
        pendingSync = true
    }

    var capacity: Capacity {
        get { Capacity(rawValue: capacityRaw) ?? .steady }
        set { capacityRaw = newValue.rawValue }
    }

    var deadlineWasPushed: Bool {
        Calendar.appDefault.startOfDay(for: deadline) > Calendar.appDefault.startOfDay(for: originalDeadline)
    }

    // MARK: - Daily state

    func isRestDay(_ day: Date) -> Bool {
        let target = Calendar.appDefault.startOfDay(for: day)
        return restDays.contains { Calendar.appDefault.startOfDay(for: $0) == target }
    }

    func tasks(on day: Date) -> [DailyTask] {
        let cal = Calendar.appDefault
        return tasks
            .filter { cal.isDate($0.date, inSameDayAs: day) }
            .sorted { $0.order < $1.order }
    }

    var todaysTasks: [DailyTask] { tasks(on: .now) }

    var upcomingTasks: [DailyTask] {
        let cal = Calendar.appDefault
        let today = cal.startOfDay(for: .now)
        return tasks
            .filter { cal.startOfDay(for: $0.date) > today }
            .sorted { $0.date < $1.date }
    }

    /// Future work still to do. The "coming up" list must be capped on *unfinished* items —
    /// capping the raw list meant that banking 7 days ahead left nothing but crossed-out
    /// rows and no visible next thing to pick up.
    var upcomingUnfinishedTasks: [DailyTask] {
        upcomingTasks.filter { !$0.isDone }
    }

    /// Tasks scheduled before today that were never checked off.
    var overdueTasks: [DailyTask] {
        let cal = Calendar.appDefault
        let today = cal.startOfDay(for: .now)
        return tasks
            .filter {
                let day = cal.startOfDay(for: $0.date)
                return day < today && !$0.isDone && !isRestDay(day)
            }
            .sorted { $0.date < $1.date }
    }

    /// Distinct past days with unfinished work — the number the user gets confronted with.
    var missedDayCount: Int {
        let cal = Calendar.appDefault
        return Set(overdueTasks.map { cal.startOfDay(for: $0.date) }).count
    }

    var isBehind: Bool { missedDayCount > 0 }

    var isDoneForToday: Bool {
        let today = todaysTasks
        return !today.isEmpty && today.allSatisfy(\.isDone)
    }

    /// Consecutive fully-completed days ending yesterday (or today if already done).
    var streak: Int {
        let cal = Calendar.appDefault
        var count = 0
        var cursor = isDoneForToday ? cal.startOfDay(for: .now)
                                    : cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: .now))!
        let start = cal.startOfDay(for: createdAt)

        while cursor >= start {
            let dayTasks = tasks(on: cursor)
            if dayTasks.isEmpty || isRestDay(cursor) {
                // Nothing scheduled, or a day the user excused: skip without breaking.
                guard let previous = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
                cursor = previous
                continue
            }
            guard dayTasks.allSatisfy(\.isDone) else { break }
            count += 1
            guard let previous = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    /// Consecutive future days, starting tomorrow, whose work is already finished.
    ///
    /// Shipping isn't fitness — running ahead is genuinely good here, not a burnout risk —
    /// so banked days are counted and celebrated rather than discouraged.
    var daysBanked: Int {
        let cal = Calendar.appDefault
        var count = 0
        var cursor = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: .now))!
        let end = cal.startOfDay(for: deadline)

        while cursor <= end {
            let dayTasks = tasks(on: cursor)
            if dayTasks.isEmpty || isRestDay(cursor) {
                guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
                cursor = next
                continue
            }
            guard dayTasks.allSatisfy(\.isDone) else { break }
            count += 1
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return count
    }

    /// How hard they're running, 0–4. Streak length is the base; banked days count double
    /// because pulling work forward is the harder, more valuable move.
    var intensity: Int {
        guard streak > 0 || daysBanked > 0 else { return 0 }
        let score = streak + (daysBanked * 2)
        switch score {
        case 0: return 0
        case 1...2: return 1
        case 3...5: return 2
        case 6...10: return 3
        default: return 4
        }
    }

    var intensityLabel: String {
        switch intensity {
        case 0: return "Cold"
        case 1: return "Warming"
        case 2: return "Rolling"
        case 3: return "Hot"
        default: return "On fire"
        }
    }

    /// The one-line summary the header and widget both use.
    var runSummary: String {
        if daysBanked > 0 {
            return "\(streak) day streak · \(daysBanked) banked"
        }
        if streak > 0 {
            return "\(streak) day streak"
        }
        return "No streak yet"
    }

    var daysRemaining: Int {
        let cal = Calendar.appDefault
        let from = cal.startOfDay(for: .now)
        let to = cal.startOfDay(for: deadline)
        return max(0, cal.dateComponents([.day], from: from, to: to).day ?? 0)
    }

    /// Every scheduled task is done — the goal's win condition.
    var isComplete: Bool {
        !tasks.isEmpty && tasks.allSatisfy(\.isDone)
    }

    var isRestDayToday: Bool { isRestDay(.now) }

    /// Days finished ahead of the deadline, once complete.
    var daysEarly: Int {
        guard isComplete else { return 0 }
        let cal = Calendar.appDefault
        let finish = cal.startOfDay(for: completedAt ?? .now)
        let due = cal.startOfDay(for: deadline)
        return max(0, cal.dateComponents([.day], from: finish, to: due).day ?? 0)
    }

    /// Share of all tasks completed, 0–1.
    var progress: Double {
        guard !tasks.isEmpty else { return 0 }
        return Double(tasks.filter(\.isDone).count) / Double(tasks.count)
    }
}

@Model
final class DailyTask {
    var date: Date
    var title: String
    var isDone: Bool
    var order: Int
    var goal: Goal?

    /// Same rationale and same fix as `Goal.syncID` — see that property's comment. Optional
    /// and undefaulted so old rows migrate as a safe NULL instead of a wiped store.
    var syncID: UUID?
    var updatedAt: Date?
    var pendingSync: Bool?

    init(date: Date, title: String, isDone: Bool = false, order: Int = 0, goal: Goal? = nil) {
        self.date = date
        self.title = title
        self.isDone = isDone
        self.order = order
        self.goal = goal
        self.syncID = UUID()
        self.updatedAt = .now
        self.pendingSync = true
    }

    var resolvedSyncID: UUID {
        if let syncID { return syncID }
        let generated = UUID()
        syncID = generated
        return generated
    }

    var resolvedUpdatedAt: Date { updatedAt ?? date }
    var needsSync: Bool { pendingSync ?? true }

    func markDirty() {
        updatedAt = .now
        pendingSync = true
    }
}

enum SharedStore {
    static let appGroupID = "group.com.vincent.shipped"

    static var container: ModelContainer = {
        let schema = Schema([
            Goal.self, DailyTask.self, ChatMessage.self, CapturedDocument.self,
            Routine.self, RoutineCheckIn.self,
        ])
        guard let groupURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
        else {
            fatalError("App Group container unavailable — check the group ID matches entitlements.")
        }
        let storeURL = groupURL.appendingPathComponent("Shipped.sqlite")
        let config = ModelConfiguration(schema: schema, url: storeURL)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create shared ModelContainer: \(error)")
        }
    }()
}

/// Formats a check-in hour for display. `.dateTime.hour()` alone renders bare "20", which
/// reads as a number rather than a time, so this uses the locale's short time style —
/// "20:00" on a 24-hour device, "8:00 PM" on a 12-hour one.
enum HourLabel {
    static func text(for hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        guard let date = Calendar.appDefault.date(from: components) else { return "\(hour)" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

extension Calendar {
    static var appDefault: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal
    }
}
