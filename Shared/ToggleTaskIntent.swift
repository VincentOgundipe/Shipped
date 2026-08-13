import AppIntents
import SwiftData
import WidgetKit

/// Lets the widget tick today's task without opening the app. For an accountability app this
/// is the highest-value interaction there is: the check-in happens where the reminder is.
struct ToggleTodayTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Tick today's task"
    static var description = IntentDescription("Marks today's next task as done.")
    /// Keeps the app in the background — tapping the widget shouldn't yank you into an app.
    static var openAppWhenRun: Bool = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        let context = ModelContext(SharedStore.container)
        let descriptor = FetchDescriptor<Goal>(
            predicate: #Predicate<Goal> { !$0.isArchived },
            sortBy: [SortDescriptor(\.priorityRank)]
        )
        let candidates = (try? context.fetch(descriptor)) ?? []

        if let goal = candidates.first(where: { !$0.isComplete }) ?? candidates.first {
            let todays = goal.todaysTasks
            // Tick the next unfinished one; if the day is already clear, untick the last so
            // the button stays reversible from the lock screen.
            if let next = todays.first(where: { !$0.isDone }) {
                next.isDone = true
            } else if let last = todays.last {
                last.isDone = false
            }
            try? context.save()
        }

        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// Same idea as `ToggleTodayTaskIntent`, for the one routine the widget shows.
struct ToggleTodayRoutineIntent: AppIntent {
    static var title: LocalizedStringResource = "Tick today's routine"
    static var description = IntentDescription("Marks today's routine activity as done.")
    static var openAppWhenRun: Bool = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        let context = ModelContext(SharedStore.container)
        let descriptor = FetchDescriptor<Routine>(predicate: #Predicate<Routine> { !$0.isArchived })
        let today = ((try? context.fetch(descriptor)) ?? []).filter { $0.isActive(on: .now) }

        if let next = today.first(where: { !$0.isDone(on: .now) }) ?? today.first {
            RoutineActions.toggleToday(next, in: context)
        }

        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
