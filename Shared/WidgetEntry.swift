import WidgetKit
import SwiftData

/// Shared between the iOS and macOS widget extensions — the data side of "what does the
/// widget show" is identical on both platforms; only the layout differs.
struct TodayEntry: TimelineEntry {
    let date: Date
    let goalTitle: String?
    let cells: [DayCell]
    let todayTaskTitle: String?
    let missedDayCount: Int
    let daysRemaining: Int
    let streak: Int
    let daysBanked: Int
    let intensity: Int
    let mode: ThemeMode
    /// One routine due today, if any — widget space is tight, so this shows only the first
    /// one still outstanding (or the last one, if everything's already done).
    var routineTitle: String? = nil
    var routineDone: Bool = false
}

struct ShippedTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(
            date: .now,
            goalTitle: "Launch my store",
            cells: sampleCells,
            todayTaskTitle: "Write 3 product descriptions",
            missedDayCount: 0,
            daysRemaining: 32,
            streak: 6,
            daysBanked: 2,
            intensity: 3,
            mode: .light
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(fetchEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let cal = Calendar.appDefault
        let nextMidnight = cal.startOfDay(
            for: cal.date(byAdding: .day, value: 1, to: .now) ?? .now
        )
        completion(Timeline(entries: [fetchEntry()], policy: .after(nextMidnight)))
    }

    private var sampleCells: [DayCell] {
        (0..<42).map { index in
            let status: DayStatus
            switch index {
            case 0..<10 where index % 4 == 3: status = .missed
            case 0..<10: status = .done
            case 10: status = .todayPending
            default: status = .future
            }
            return DayCell(id: index, date: .now, status: status)
        }
    }

    private func fetchEntry() -> TodayEntry {
        let mode = AppSettings.themeMode
        let context = ModelContext(SharedStore.container)

        let routineDescriptor = FetchDescriptor<Routine>(
            predicate: #Predicate<Routine> { !$0.isArchived }
        )
        let routinesToday = ((try? context.fetch(routineDescriptor)) ?? [])
            .filter { $0.isActive(on: .now) }
        let routine = routinesToday.first(where: { !$0.isDone(on: .now) }) ?? routinesToday.first
        let routineTitle = routine.flatMap { $0.activity(for: .now)?.title ?? $0.title }
        let routineDone = routine?.isDone(on: .now) ?? false

        let descriptor = FetchDescriptor<Goal>(
            predicate: #Predicate<Goal> { !$0.isArchived },
            sortBy: [SortDescriptor(\.priorityRank)]
        )
        // Prefer the top-priority goal that's still active — a completed-but-unarchived one
        // sitting at rank 0 would otherwise show a stale "done" widget.
        let candidates = (try? context.fetch(descriptor)) ?? []
        guard let goal = candidates.first(where: { !$0.isComplete }) ?? candidates.first else {
            return TodayEntry(
                date: .now, goalTitle: nil, cells: [], todayTaskTitle: nil,
                missedDayCount: 0, daysRemaining: 0,
                streak: 0, daysBanked: 0, intensity: 0, mode: mode,
                routineTitle: routineTitle, routineDone: routineDone
            )
        }

        let pending = goal.todaysTasks.first { !$0.isDone }
        return TodayEntry(
            date: .now,
            goalTitle: goal.title,
            cells: GoalGrid.cells(for: goal),
            todayTaskTitle: pending?.title,
            missedDayCount: goal.missedDayCount,
            daysRemaining: goal.daysRemaining,
            streak: goal.streak,
            daysBanked: goal.daysBanked,
            intensity: goal.intensity,
            mode: mode,
            routineTitle: routineTitle,
            routineDone: routineDone
        )
    }
}
