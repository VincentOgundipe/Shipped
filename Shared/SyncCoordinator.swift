import Foundation
import SwiftData

/// Pushes local changes up, pulls remote changes down, merges by last-write-wins on
/// `updatedAt`. Runs on both platforms against the same Supabase tables, scoped by
/// `Secrets.syncGroupID` — that string is what makes the phone and the Mac "the same person"
/// without real per-user auth.
@MainActor
enum SyncCoordinator {
    private static let lastPulledKey = "sync.lastPulledAt"
    private static let lastSyncKey = "sync.lastSyncedAt"

    static var isConfigured: Bool { SupabaseSync.isConfigured }

    static var lastSyncedAt: Date? {
        get { AppSettings.defaults.object(forKey: lastSyncKey) as? Date }
        set { AppSettings.defaults.set(newValue, forKey: lastSyncKey) }
    }

    private static var lastPulledAt: Date {
        get { (AppSettings.defaults.object(forKey: lastPulledKey) as? Date) ?? .distantPast }
        set { AppSettings.defaults.set(newValue, forKey: lastPulledKey) }
    }

    /// Runs a full push-then-pull pass. Safe to call often — a no-op when there's nothing
    /// dirty and nothing new upstream.
    static func sync(in context: ModelContext) async throws {
        guard isConfigured else { throw SupabaseSyncError.notConfigured }
        try await push(in: context)
        try await pull(in: context)
        lastSyncedAt = .now
    }

    // MARK: - Push

    private static func push(in context: ModelContext) async throws {
        // `pendingSync` is optional (see Models.swift for why) — nil means "never touched by
        // sync code", which must count as dirty too, or a row from before this field existed
        // would never get pushed at all.
        let goals = try context.fetch(FetchDescriptor<Goal>(
            predicate: #Predicate { $0.pendingSync == true || $0.pendingSync == nil }
        ))
        if !goals.isEmpty {
            try await SupabaseSync.upsert(table: "goals", rows: goals.map(goalRow))
            for goal in goals { goal.pendingSync = false }
        }

        let tasks = try context.fetch(FetchDescriptor<DailyTask>(
            predicate: #Predicate { $0.pendingSync == true || $0.pendingSync == nil }
        ))
        // `goal_id` is NOT NULL on the server — an orphaned task (no goal) would fail the
        // whole batch upsert, so it's filtered out here rather than sent.
        let attachedTasks = tasks.filter { $0.goal != nil }
        if !attachedTasks.isEmpty {
            try await SupabaseSync.upsert(table: "daily_tasks", rows: attachedTasks.map(taskRow))
            for task in attachedTasks { task.pendingSync = false }
        }

        let routines = try context.fetch(FetchDescriptor<Routine>(
            predicate: #Predicate { $0.pendingSync == true || $0.pendingSync == nil }
        ))
        if !routines.isEmpty {
            try await SupabaseSync.upsert(table: "routines", rows: routines.map(routineRow))
            for routine in routines { routine.pendingSync = false }
        }

        let checkIns = try context.fetch(FetchDescriptor<RoutineCheckIn>(
            predicate: #Predicate { $0.pendingSync == true || $0.pendingSync == nil }
        ))
        let attachedCheckIns = checkIns.filter { $0.routine != nil }
        if !attachedCheckIns.isEmpty {
            try await SupabaseSync.upsert(table: "routine_checkins", rows: attachedCheckIns.map(checkInRow))
            for checkIn in attachedCheckIns { checkIn.pendingSync = false }
        }

        try context.save()
    }

    // MARK: - Pull

    private static func pull(in context: ModelContext) async throws {
        let remoteGoals = try await SupabaseSync.fetchChanged(table: "goals", since: lastPulledAt)
        let remoteTasks = try await SupabaseSync.fetchChanged(table: "daily_tasks", since: lastPulledAt)
        let remoteRoutines = try await SupabaseSync.fetchChanged(table: "routines", since: lastPulledAt)
        let remoteCheckIns = try await SupabaseSync.fetchChanged(table: "routine_checkins", since: lastPulledAt)

        for row in remoteGoals { try mergeGoal(row, in: context) }
        // Goals/routines must exist locally before their tasks/check-ins can attach to them.
        for row in remoteTasks { try mergeTask(row, in: context) }
        for row in remoteRoutines { try mergeRoutine(row, in: context) }
        for row in remoteCheckIns { try mergeCheckIn(row, in: context) }

        let newest = (
            remoteGoals.map(\.updated_at) + remoteTasks.map(\.updated_at)
                + remoteRoutines.map(\.updated_at) + remoteCheckIns.map(\.updated_at)
        ).max()
        if let newest { lastPulledAt = newest }
        try context.save()
    }

    private static func mergeGoal(_ row: SyncRow, in context: ModelContext) throws {
        let targetID: UUID? = row.id
        let existing = try context.fetch(
            FetchDescriptor<Goal>(predicate: #Predicate { $0.syncID == targetID })
        ).first

        if let existing {
            // Last-write-wins: a remote row only overwrites local fields if it's actually
            // newer, so pushing our own not-yet-acknowledged edits back doesn't clobber them.
            guard row.updated_at > existing.resolvedUpdatedAt else { return }
            apply(row, to: existing)
        } else if !row.deleted {
            let goal = Goal(
                title: row.title,
                deadline: row.deadline ?? .now,
                createdAt: row.created_at ?? .now,
                capacity: Capacity(rawValue: row.capacity ?? "") ?? .steady,
                checkInHour: row.check_in_hour ?? 20
            )
            goal.syncID = row.id
            apply(row, to: goal)
            context.insert(goal)
        }
    }

    private static func apply(_ row: SyncRow, to goal: Goal) {
        goal.title = row.title
        if let d = row.deadline { goal.deadline = d }
        if let od = row.original_deadline { goal.originalDeadline = od }
        goal.capacityRaw = row.capacity ?? goal.capacityRaw
        goal.checkInHour = row.check_in_hour ?? goal.checkInHour
        goal.recutCount = row.recut_count ?? goal.recutCount
        goal.isArchived = row.is_archived ?? goal.isArchived
        goal.completedAt = row.completed_at
        goal.restDays = row.rest_days ?? goal.restDays
        goal.updatedAt = row.updated_at
        goal.pendingSync = false
    }

    private static func mergeTask(_ row: SyncRow, in context: ModelContext) throws {
        guard let goalID = row.goal_id else { return }
        let targetGoalID: UUID? = goalID
        guard let goal = try context.fetch(
            FetchDescriptor<Goal>(predicate: #Predicate { $0.syncID == targetGoalID })
        ).first else { return }

        let targetID: UUID? = row.id
        let existing = try context.fetch(
            FetchDescriptor<DailyTask>(predicate: #Predicate { $0.syncID == targetID })
        ).first

        if let existing {
            guard row.updated_at > existing.resolvedUpdatedAt else { return }
            if row.deleted {
                context.delete(existing)
                return
            }
            existing.date = row.date ?? existing.date
            existing.title = row.title
            existing.isDone = row.is_done ?? existing.isDone
            existing.order = row.task_order ?? existing.order
            existing.updatedAt = row.updated_at
            existing.pendingSync = false
        } else if !row.deleted {
            let task = DailyTask(
                date: row.date ?? .now,
                title: row.title,
                isDone: row.is_done ?? false,
                order: row.task_order ?? 0,
                goal: goal
            )
            task.syncID = row.id
            task.updatedAt = row.updated_at
            task.pendingSync = false
            context.insert(task)
        }
    }

    private static func mergeRoutine(_ row: SyncRow, in context: ModelContext) throws {
        let targetID: UUID? = row.id
        let existing = try context.fetch(
            FetchDescriptor<Routine>(predicate: #Predicate { $0.syncID == targetID })
        ).first

        if let existing {
            guard row.updated_at > existing.resolvedUpdatedAt else { return }
            if row.deleted {
                context.delete(existing)
                return
            }
            apply(row, to: existing)
        } else if !row.deleted {
            let routine = Routine(
                title: row.title,
                activeWeekdays: row.active_weekdays ?? [],
                activities: row.activities ?? [],
                createdAt: row.created_at ?? .now
            )
            routine.syncID = row.id
            apply(row, to: routine)
            context.insert(routine)
        }
    }

    private static func apply(_ row: SyncRow, to routine: Routine) {
        routine.title = row.title
        routine.activeWeekdays = row.active_weekdays ?? routine.activeWeekdays
        routine.activities = row.activities ?? routine.activities
        routine.isArchived = row.is_archived ?? routine.isArchived
        routine.updatedAt = row.updated_at
        routine.pendingSync = false
    }

    private static func mergeCheckIn(_ row: SyncRow, in context: ModelContext) throws {
        guard let routineID = row.routine_id else { return }
        let targetRoutineID: UUID? = routineID
        guard let routine = try context.fetch(
            FetchDescriptor<Routine>(predicate: #Predicate { $0.syncID == targetRoutineID })
        ).first else { return }

        let targetID: UUID? = row.id
        let existing = try context.fetch(
            FetchDescriptor<RoutineCheckIn>(predicate: #Predicate { $0.syncID == targetID })
        ).first

        if let existing {
            guard row.updated_at > existing.resolvedUpdatedAt else { return }
            if row.deleted {
                context.delete(existing)
                return
            }
            existing.date = row.date ?? existing.date
            existing.isDone = row.is_done ?? existing.isDone
            existing.updatedAt = row.updated_at
            existing.pendingSync = false
        } else if !row.deleted {
            let checkIn = RoutineCheckIn(
                date: row.date ?? .now,
                isDone: row.is_done ?? true,
                routine: routine
            )
            checkIn.syncID = row.id
            checkIn.updatedAt = row.updated_at
            checkIn.pendingSync = false
            context.insert(checkIn)
        }
    }

    // MARK: - Wire mapping

    private static func goalRow(_ goal: Goal) -> SyncRow {
        SyncRow(
            id: goal.resolvedSyncID,
            sync_group: Secrets.syncGroupID,
            title: goal.title,
            deadline: goal.deadline,
            original_deadline: goal.originalDeadline,
            created_at: goal.createdAt,
            capacity: goal.capacityRaw,
            check_in_hour: goal.checkInHour,
            recut_count: goal.recutCount,
            is_archived: goal.isArchived,
            completed_at: goal.completedAt,
            rest_days: goal.restDays,
            updated_at: goal.resolvedUpdatedAt
        )
    }

    private static func taskRow(_ task: DailyTask) -> SyncRow {
        SyncRow(
            id: task.resolvedSyncID,
            sync_group: Secrets.syncGroupID,
            goal_id: task.goal?.resolvedSyncID,
            title: task.title,
            date: task.date,
            is_done: task.isDone,
            task_order: task.order,
            updated_at: task.resolvedUpdatedAt
        )
    }

    private static func routineRow(_ routine: Routine) -> SyncRow {
        SyncRow(
            id: routine.resolvedSyncID,
            sync_group: Secrets.syncGroupID,
            title: routine.title,
            created_at: routine.createdAt,
            is_archived: routine.isArchived,
            active_weekdays: routine.activeWeekdays,
            activities: routine.activities,
            updated_at: routine.resolvedUpdatedAt
        )
    }

    private static func checkInRow(_ checkIn: RoutineCheckIn) -> SyncRow {
        SyncRow(
            id: checkIn.resolvedSyncID,
            sync_group: Secrets.syncGroupID,
            routine_id: checkIn.routine?.resolvedSyncID,
            title: "",
            date: checkIn.date,
            is_done: checkIn.isDone,
            updated_at: checkIn.resolvedUpdatedAt
        )
    }

    /// Marks a goal deleted upstream before removing it locally, so the other device learns
    /// about the deletion on its next pull instead of the row just silently reappearing there
    /// forever because it never got told to stop existing.
    static func pushTombstone(for goal: Goal) async {
        guard isConfigured else { return }
        var row = goalRow(goal)
        row.deleted = true
        row.updated_at = .now
        try? await SupabaseSync.upsert(table: "goals", rows: [row])
    }
}
