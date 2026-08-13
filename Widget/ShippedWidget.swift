import WidgetKit
import SwiftUI
import SwiftData

struct ShippedWidgetView: View {
    var entry: TodayEntry
    @Environment(\.widgetFamily) private var family

    private var palette: ThemePalette { Theme.palette(for: entry.mode) }

    /// The grid's cells already carry real dates internally with nothing surfacing them —
    /// this makes the timeframe visible without needing per-cell labels, which wouldn't fit.
    private var dateRangeLabel: String? {
        guard let first = entry.cells.first?.date, let last = entry.cells.last?.date else { return nil }
        let format = Date.FormatStyle().month(.abbreviated).day()
        return "\(first.formatted(format)) – \(last.formatted(format))"
    }

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

                if let range = dateRangeLabel {
                    Text(range)
                        .font(.system(size: 8))
                        .foregroundStyle(palette.textTertiary)
                }

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

                    if let routineTitle = entry.routineTitle {
                        HStack(alignment: .top, spacing: 7) {
                            Button(intent: ToggleTodayRoutineIntent()) {
                                Image(systemName: entry.routineDone ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 15))
                                    .foregroundStyle(entry.routineDone ? palette.accent : palette.textSecondary)
                            }
                            .buttonStyle(.plain)

                            Text(routineTitle)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(entry.routineDone ? palette.textSecondary : palette.text)
                                .strikethrough(entry.routineDone)
                                .lineLimit(1)
                        }
                    }
                }
            } else if let routineTitle = entry.routineTitle {
                Spacer()
                HStack(spacing: 7) {
                    Button(intent: ToggleTodayRoutineIntent()) {
                        Image(systemName: entry.routineDone ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 15))
                            .foregroundStyle(entry.routineDone ? palette.accent : palette.textSecondary)
                    }
                    .buttonStyle(.plain)
                    Text(routineTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(entry.routineDone ? palette.textSecondary : palette.text)
                        .strikethrough(entry.routineDone)
                        .lineLimit(1)
                }
                Spacer()
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
            } else if let routineTitle = entry.routineTitle, !entry.routineDone {
                Text("TODAY")
                    .font(.system(size: 9, weight: .bold))
                Text(routineTitle)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
            } else if entry.routineTitle != nil {
                Text("DONE TODAY")
                    .font(.system(size: 9, weight: .bold))
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
