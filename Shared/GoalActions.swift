import Foundation
import SwiftData

/// Operations that change a goal's lifecycle. Kept out of the views so iOS and macOS behave
/// identically — they were drifting apart when each screen did its own bookkeeping.
enum GoalActions {

    // MARK: - Archiving

    /// Retires a goal without deleting it. Queries filter archived goals out, which is what
    /// stops a newly created goal from silently hiding the old one.
    static func archive(_ goal: Goal, in context: ModelContext, completed: Bool) {
        goal.isArchived = true
        if completed && goal.completedAt == nil {
            goal.completedAt = .now
        }
        goal.markDirty()
        try? context.save()
    }

    // MARK: - Rest days

    /// Excuses today: the streak survives, and today's unfinished work moves to tomorrow
    /// rather than evaporating. Deferring is honest; forgiving the work would not be.
    static func takeRestDay(_ goal: Goal, in context: ModelContext) {
        let cal = Calendar.appDefault
        let today = cal.startOfDay(for: .now)
        guard !goal.isRestDay(today) else { return }

        goal.restDays.append(today)
        goal.markDirty()

        if let tomorrow = cal.date(byAdding: .day, value: 1, to: today) {
            for task in goal.todaysTasks where !task.isDone {
                task.date = tomorrow
            }
            // Keep the deadline reachable if the shift pushed work past it.
            if tomorrow > cal.startOfDay(for: goal.deadline) {
                goal.deadline = tomorrow
            }
        }
        try? context.save()
    }

    static func undoRestDay(_ goal: Goal, in context: ModelContext) {
        let cal = Calendar.appDefault
        let today = cal.startOfDay(for: .now)
        goal.restDays.removeAll { cal.startOfDay(for: $0) == today }
        goal.markDirty()
        try? context.save()
    }

    // MARK: - Recut snapshots

    private struct TaskRecord: Codable {
        let date: Date
        let title: String
        let isDone: Bool
        let order: Int
    }

    private struct PlanSnapshot: Codable {
        let deadline: Date
        let tasks: [TaskRecord]
    }

    /// Captures the plan so a recut can be reversed. Called immediately before a recut.
    static func snapshotPlan(_ goal: Goal) {
        let snapshot = PlanSnapshot(
            deadline: goal.deadline,
            tasks: goal.tasks.map {
                TaskRecord(date: $0.date, title: $0.title, isDone: $0.isDone, order: $0.order)
            }
        )
        goal.planSnapshot = try? JSONEncoder().encode(snapshot)
    }

    static func canUndoRecut(_ goal: Goal) -> Bool { goal.planSnapshot != nil }

    /// Restores the pre-recut plan, including completion state and the old deadline.
    static func undoRecut(_ goal: Goal, in context: ModelContext) {
        guard let data = goal.planSnapshot,
              let snapshot = try? JSONDecoder().decode(PlanSnapshot.self, from: data)
        else { return }

        for task in goal.tasks { context.delete(task) }
        for record in snapshot.tasks {
            context.insert(
                DailyTask(
                    date: record.date,
                    title: record.title,
                    isDone: record.isDone,
                    order: record.order,
                    goal: goal
                )
            )
        }
        goal.deadline = snapshot.deadline
        goal.recutCount = max(0, goal.recutCount - 1)
        goal.markDirty()
        goal.planSnapshot = nil
        try? context.save()
    }

    // MARK: - Export

    private struct GoalExport: Codable {
        struct Task: Codable {
            let date: Date
            let title: String
            let isDone: Bool
        }
        let title: String
        let createdAt: Date
        let deadline: Date
        let originalDeadline: Date
        let pace: String
        let isArchived: Bool
        let completedAt: Date?
        let restDays: [Date]
        let recutCount: Int
        let tasks: [Task]
    }

    /// Plain JSON so the history isn't trapped in a single SQLite file. Includes archived
    /// goals, since those are the record of what actually got shipped.
    static func exportJSON(from context: ModelContext) -> Data? {
        let descriptor = FetchDescriptor<Goal>(sortBy: [SortDescriptor(\.createdAt)])
        guard let goals = try? context.fetch(descriptor) else { return nil }

        let payload = goals.map { goal in
            GoalExport(
                title: goal.title,
                createdAt: goal.createdAt,
                deadline: goal.deadline,
                originalDeadline: goal.originalDeadline,
                pace: goal.capacity.rawValue,
                isArchived: goal.isArchived,
                completedAt: goal.completedAt,
                restDays: goal.restDays,
                recutCount: goal.recutCount,
                tasks: goal.tasks
                    .sorted { $0.date < $1.date }
                    .map { GoalExport.Task(date: $0.date, title: $0.title, isDone: $0.isDone) }
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(payload)
    }

    static var exportFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "shipped-export-\(formatter.string(from: .now)).json"
    }
}
