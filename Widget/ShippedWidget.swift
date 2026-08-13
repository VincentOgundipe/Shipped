import WidgetKit
import SwiftUI
import SwiftData

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
        let descriptor = FetchDescriptor<Goal>(
            predicate: #Predicate<Goal> { !$0.isArchived },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        guard let goal = try? context.fetch(descriptor).first else {
            return TodayEntry(
                date: .now, goalTitle: nil, cells: [], todayTaskTitle: nil,
                missedDayCount: 0, daysRemaining: 0,
                streak: 0, daysBanked: 0, intensity: 0, mode: mode
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
            mode: mode
        )
    }
}

struct ShippedWidgetView: View {
    var entry: TodayEntry
    @Environment(\.widgetFamily) private var family

    private var palette: ThemePalette { Theme.palette(for: entry.mode) }

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular:
                accessoryView
            default:
                homeView
            }
        }
    }

    // MARK: - Home / lock screen grid

    private var homeView: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let goalTitle = entry.goalTitle {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(entry.missedDayCount > 0 ? entry.missedDayCount : entry.daysRemaining)")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(entry.missedDayCount > 0
                                         ? palette.accentSecondary : palette.text)
                    Text(entry.missedDayCount > 0 ? "missed" : "days left")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textSecondary)
                    Spacer(minLength: 2)
                    StreakFlame(level: entry.intensity, palette: palette,
                                size: 20, animated: false)
                }

                Text(goalTitle.uppercased())
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)

                ProgressGridView(
                    cells: entry.cells,
                    palette: palette,
                    columns: family == .systemSmall ? 8 : 16,
                    spacing: 2.5,
                    cornerRadius: 2
                )

                HStack(spacing: 5) {
                    Text(entry.streak > 0 ? "\(entry.streak) day streak" : "No streak")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(entry.streak > 0 ? palette.accent : palette.textTertiary)
                    if entry.daysBanked > 0 {
                        Text("+\(entry.daysBanked) banked")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(palette.accentSecondary)
                    }
                }
                .padding(.top, 1)

                if family != .systemSmall {
                    HStack(alignment: .top, spacing: 7) {
                        // Interactive widget: check in without opening the app.
                        Button(intent: ToggleTodayTaskIntent()) {
                            Image(systemName: entry.todayTaskTitle == nil
                                  ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 15))
                                .foregroundStyle(entry.todayTaskTitle == nil
                                                 ? palette.accent : palette.textSecondary)
                        }
                        .buttonStyle(.plain)

                        Text(entry.todayTaskTitle ?? "Done for today")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(entry.todayTaskTitle == nil
                                             ? palette.textSecondary : palette.text)
                            .strikethrough(entry.todayTaskTitle == nil)
                            .lineLimit(2)
                    }
                    .padding(.top, 1)
                }
            } else {
                Spacer()
                Text("NO GOAL SET")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(palette.textSecondary)
                Text("Open Shipped to start one")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textTertiary)
                Spacer()
            }
        }
    }

    // MARK: - Lock screen inline

    private var accessoryView: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let task = entry.todayTaskTitle {
                Text("TODAY")
                    .font(.system(size: 9, weight: .bold))
                Text(task)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
            } else if entry.goalTitle != nil {
                Text("DONE TODAY")
                    .font(.system(size: 9, weight: .bold))
                Text(entry.daysBanked > 0
                     ? "\(entry.streak) streak · +\(entry.daysBanked) banked"
                     : "\(entry.streak) day streak")
                    .font(.system(size: 12, weight: .medium))
            } else {
                Text("No goal set")
                    .font(.system(size: 12, weight: .medium))
            }
        }
    }
}

struct ShippedWidget: Widget {
    let kind: String = "ShippedWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ShippedTimelineProvider()) { entry in
            ShippedWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Theme.palette(for: entry.mode).background
                }
        }
        .configurationDisplayName("Progress Grid")
        .description("One square per day. Fills in as you ship, stays red when you don't.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}
