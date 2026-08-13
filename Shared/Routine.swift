import Foundation
import SwiftData

/// A single scheduled activity within a routine's weekly shape.
///
/// Activities are edited as a whole rather than as individually-synced rows — a weekly split
/// is small and changes as a unit (swap a day, rename an exercise), so it's stored as encoded
/// data on the `Routine` itself instead of its own relational/sync table.
struct RoutineActivityItem: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var title: String
    /// nil means "every day the routine is active"; a specific weekday (1=Sunday...7=Saturday,
    /// matching `Calendar`'s `.weekday` component) is for day-varying routines like a
    /// Push/Pull/Legs split.
    var weekday: Int?
}

/// Something the user does on a recurring basis with no end date — a workout split, a daily
/// reading habit — as opposed to a `Goal`, which counts down to a deadline. Completion is
/// tracked per-day via `RoutineCheckIn` rows created lazily, rather than pre-materializing
/// tasks forever the way a `Goal`'s finite plan does.
@Model
final class Routine {
    var title: String
    var createdAt: Date

    /// Weekdays this routine runs, 1=Sunday...7=Saturday (matches `Calendar`'s `.weekday`).
    var activeWeekdays: [Int]

    /// Retired routines stay in the store for history but drop out of every query, matching
    /// how `Goal.isArchived` works.
    var isArchived: Bool = false

    private var activitiesData: Data

    /// Same rationale as `Goal.syncID` — optional and undefaulted so old rows migrate as a
    /// safe NULL instead of a wiped store. See that property's comment for the full story.
    var syncID: UUID?
    var updatedAt: Date?
    var pendingSync: Bool?

    @Relationship(deleteRule: .cascade, inverse: \RoutineCheckIn.routine)
    var checkIns: [RoutineCheckIn] = []

    init(
        title: String,
        activeWeekdays: [Int],
        activities: [RoutineActivityItem],
        createdAt: Date = .now
    ) {
        self.title = title
        self.activeWeekdays = activeWeekdays
        self.createdAt = createdAt
        self.activitiesData = (try? JSONEncoder().encode(activities)) ?? Data()
        self.syncID = UUID()
        self.updatedAt = createdAt
        self.pendingSync = true
    }

    var activities: [RoutineActivityItem] {
        get { (try? JSONDecoder().decode([RoutineActivityItem].self, from: activitiesData)) ?? [] }
        set {
            activitiesData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    var resolvedSyncID: UUID {
        if let syncID { return syncID }
        let generated = UUID()
        syncID = generated
        return generated
    }

    var resolvedUpdatedAt: Date { updatedAt ?? createdAt }
    var needsSync: Bool { pendingSync ?? true }

    func markDirty() {
        updatedAt = .now
        pendingSync = true
    }

    func isActive(on date: Date) -> Bool {
        activeWeekdays.contains(Calendar.appDefault.component(.weekday, from: date))
    }

    /// The activity scheduled for a date, if the routine runs that day. A day-specific entry
    /// (e.g. "Push" on Monday) wins over a catch-all every-day entry.
    func activity(for date: Date) -> RoutineActivityItem? {
        guard isActive(on: date) else { return nil }
        let weekday = Calendar.appDefault.component(.weekday, from: date)
        return activities.first { $0.weekday == weekday } ?? activities.first { $0.weekday == nil }
    }

    func isDone(on date: Date) -> Bool {
        checkIns.contains {
            Calendar.appDefault.isDate($0.date, inSameDayAs: date) && $0.isDone
        }
    }

    var isDoneToday: Bool { !isActive(on: .now) || isDone(on: .now) }

    /// Consecutive active days, ending today (or yesterday if today isn't checked off yet),
    /// that were completed. Inactive days don't break it — they just aren't counted.
    var streak: Int {
        let cal = Calendar.appDefault
        var cursor = cal.startOfDay(for: .now)
        if isActive(on: cursor) && !isDone(on: cursor) {
            guard let yesterday = cal.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }
        let start = cal.startOfDay(for: createdAt)
        var count = 0
        while cursor >= start {
            if isActive(on: cursor) {
                guard isDone(on: cursor) else { break }
                count += 1
            }
            guard let previous = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }
}

@Model
final class RoutineCheckIn {
    var date: Date
    var isDone: Bool
    var routine: Routine?

    var syncID: UUID?
    var updatedAt: Date?
    var pendingSync: Bool?

    init(date: Date, isDone: Bool = true, routine: Routine?) {
        self.date = Calendar.appDefault.startOfDay(for: date)
        self.isDone = isDone
        self.routine = routine
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

enum RoutineActions {
    static func toggleToday(_ routine: Routine, in context: ModelContext) {
        toggle(routine, on: .now, in: context)
    }

    static func toggle(_ routine: Routine, on date: Date, in context: ModelContext) {
        let day = Calendar.appDefault.startOfDay(for: date)
        if let existing = routine.checkIns.first(where: { Calendar.appDefault.isDate($0.date, inSameDayAs: day) }) {
            existing.isDone.toggle()
            existing.markDirty()
        } else {
            context.insert(RoutineCheckIn(date: day, isDone: true, routine: routine))
        }
        routine.markDirty()
        try? context.save()
    }

    static func archive(_ routine: Routine, in context: ModelContext) {
        routine.isArchived = true
        routine.markDirty()
        try? context.save()
    }
}

/// Weekday display helpers. `Calendar`'s `.weekday` component is 1=Sunday...7=Saturday
/// regardless of locale, so these arrays are indexed the same way (index 0 unused).
enum Weekday {
    static let shortNames = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    static let fullNames = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    /// Monday-first display order, since that's how most people think about a week — only
    /// `Calendar`'s underlying numbering stays Sunday-first.
    static let displayOrder = [2, 3, 4, 5, 6, 7, 1]

    static func short(_ weekday: Int) -> String {
        guard (1...7).contains(weekday) else { return "" }
        return shortNames[weekday]
    }

    static func full(_ weekday: Int) -> String {
        guard (1...7).contains(weekday) else { return "" }
        return fullNames[weekday]
    }
}
