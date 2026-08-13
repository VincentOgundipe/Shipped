import SwiftUI

enum DayStatus {
    case done
    /// A future day already finished — work banked ahead of schedule.
    case ahead
    case missed
    case todayPending
    case todayDone
    case future
    case empty

    func color(_ palette: ThemePalette) -> Color {
        switch self {
        case .done: return palette.gridDone
        case .ahead: return palette.gridDone
        case .todayDone: return palette.gridDone
        case .missed: return palette.gridMissed
        case .todayPending: return palette.gridToday.opacity(0.18)
        case .future: return palette.gridFuture
        case .empty: return palette.gridEmpty
        }
    }

    func strokeColor(_ palette: ThemePalette) -> Color {
        switch self {
        case .todayPending, .todayDone: return palette.gridToday
        case .ahead: return palette.accentSecondary
        default: return .clear
        }
    }

    var isToday: Bool {
        self == .todayPending || self == .todayDone
    }
}

struct DayCell: Identifiable, Equatable {
    let id: Int
    let date: Date
    let status: DayStatus

    static func == (lhs: DayCell, rhs: DayCell) -> Bool {
        lhs.id == rhs.id && lhs.status == rhs.status
    }
}

enum GoalGrid {
    /// One cell per day from the goal's start through its deadline.
    static func cells(for goal: Goal) -> [DayCell] {
        let cal = Calendar.appDefault
        let today = cal.startOfDay(for: .now)
        let start = cal.startOfDay(for: goal.createdAt)
        let end = cal.startOfDay(for: goal.deadline)
        guard start <= end else { return [] }

        var tasksByDay: [Date: [DailyTask]] = [:]
        for task in goal.tasks {
            tasksByDay[cal.startOfDay(for: task.date), default: []].append(task)
        }

        var cells: [DayCell] = []
        var cursor = start
        var index = 0
        while cursor <= end {
            let dayTasks = tasksByDay[cursor] ?? []
            let allDone = !dayTasks.isEmpty && dayTasks.allSatisfy(\.isDone)

            let status: DayStatus
            if cursor == today {
                status = allDone ? .todayDone : .todayPending
            } else if cursor < today {
                status = dayTasks.isEmpty ? .empty : (allDone ? .done : .missed)
            } else {
                // Future days count as banked once their work is done.
                status = allDone ? .ahead : .future
            }

            cells.append(DayCell(id: index, date: cursor, status: status))
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
            index += 1
        }
        return cells
    }
}

struct ProgressGridView: View {
    let cells: [DayCell]
    let palette: ThemePalette
    var columns: Int = 14
    var spacing: CGFloat = 4
    var cornerRadius: CGFloat = 3
    /// Animates cells in on appear. Off in the widget, where animation isn't available.
    var animateOnAppear: Bool = false

    @State private var revealed = false

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns),
            spacing: spacing
        ) {
            ForEach(cells) { cell in
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(cell.status.color(palette))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(cell.status.strokeColor(palette), lineWidth: 1.5)
                    )
                    .scaleEffect(revealed ? 1 : 0.4)
                    .opacity(revealed ? 1 : 0)
                    .animation(
                        .spring(response: 0.4, dampingFraction: 0.75)
                            .delay(animateOnAppear ? Double(cell.id) * 0.008 : 0),
                        value: revealed
                    )
                    .animation(.spring(response: 0.35, dampingFraction: 0.6), value: cell.status)
            }
        }
        .onAppear {
            if animateOnAppear {
                revealed = true
            } else {
                revealed = true
            }
        }
    }
}
