import WidgetKit
import SwiftUI

/// Desktop/Notification Center widget for the Mac. Shares `TodayEntry` and
/// `ShippedTimelineProvider` with the iOS widget (Shared/WidgetEntry.swift) — only the layout
/// differs, since macOS has no lock screen and supports `.systemLarge` instead.
struct MacShippedWidgetView: View {
    var entry: TodayEntry
    @Environment(\.widgetFamily) private var family

    private var palette: ThemePalette { Theme.palette(for: entry.mode) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let goalTitle = entry.goalTitle {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(entry.missedDayCount > 0 ? entry.missedDayCount : entry.daysRemaining)")
                        .font(.system(size: family == .systemSmall ? 26 : 32, weight: .semibold))
                        .foregroundStyle(entry.missedDayCount > 0 ? palette.accentSecondary : palette.text)
                    Text(entry.missedDayCount > 0 ? "missed" : "days left")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.textSecondary)
                    Spacer(minLength: 2)
                    StreakFlame(level: entry.intensity, palette: palette, size: 22, animated: false)
                }

                Text(goalTitle.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)

                ProgressGridView(
                    cells: entry.cells,
                    palette: palette,
                    columns: family == .systemSmall ? 8 : (family == .systemLarge ? 20 : 16),
                    spacing: 2.5,
                    cornerRadius: 2
                )

                HStack(spacing: 6) {
                    Text(entry.streak > 0 ? "\(entry.streak) day streak" : "No streak")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(entry.streak > 0 ? palette.accent : palette.textTertiary)
                    if entry.daysBanked > 0 {
                        Text("+\(entry.daysBanked) banked")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(palette.accentSecondary)
                    }
                }
                .padding(.top, 1)

                if family != .systemSmall {
                    Button(intent: ToggleTodayTaskIntent()) {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: entry.todayTaskTitle == nil ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 16))
                                .foregroundStyle(entry.todayTaskTitle == nil ? palette.accent : palette.textSecondary)
                            Text(entry.todayTaskTitle ?? "Done for today")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(entry.todayTaskTitle == nil ? palette.textSecondary : palette.text)
                                .strikethrough(entry.todayTaskTitle == nil)
                                .lineLimit(2)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)

                    if let routineTitle = entry.routineTitle {
                        Button(intent: ToggleTodayRoutineIntent()) {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: entry.routineDone ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 16))
                                    .foregroundStyle(entry.routineDone ? palette.accent : palette.textSecondary)
                                Text(routineTitle)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(entry.routineDone ? palette.textSecondary : palette.text)
                                    .strikethrough(entry.routineDone)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if let routineTitle = entry.routineTitle {
                Spacer()
                Button(intent: ToggleTodayRoutineIntent()) {
                    HStack(spacing: 8) {
                        Image(systemName: entry.routineDone ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16))
                            .foregroundStyle(entry.routineDone ? palette.accent : palette.textSecondary)
                        Text(routineTitle)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(entry.routineDone ? palette.textSecondary : palette.text)
                            .strikethrough(entry.routineDone)
                    }
                }
                .buttonStyle(.plain)
                Spacer()
            } else {
                Spacer()
                Text("NO GOAL SET")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(palette.textSecondary)
                Text("Open Shipped to start one")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textTertiary)
                Spacer()
            }
        }
    }
}

struct MacShippedWidget: Widget {
    let kind: String = "MacShippedWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ShippedTimelineProvider()) { entry in
            MacShippedWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Theme.palette(for: entry.mode).background
                }
        }
        .configurationDisplayName("Progress Grid")
        .description("One square per day. Fills in as you ship, stays red when you don't.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
