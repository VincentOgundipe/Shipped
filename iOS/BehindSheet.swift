import SwiftUI
import SwiftData
import WidgetKit

/// Shown when the user opens the app with unfinished past days. Confronts them with the
/// number, then makes them choose what it costs: time, or intensity.
struct BehindSheet: View {
    @Bindable var goal: Goal
    @Environment(\.modelContext) private var context
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var isRecutting = false
    @State private var errorMessage: String?
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Missed").labelStyle(palette)

                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(goal.missedDayCount)")
                                .font(.system(size: 56, weight: palette.displayWeight))
                                .foregroundStyle(palette.accent)
                                .contentTransition(.numericText())
                            Text(goal.missedDayCount == 1 ? "day" : "days")
                                .displayStyle(palette, size: TypeScale.headingSm)
                        }
                        .scaleEffect(appeared ? 1 : 0.8)
                        .opacity(appeared ? 1 : 0)
                        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: appeared)

                        Text("\(goal.overdueTasks.count) task\(goal.overdueTasks.count == 1 ? "" : "s") never got done. That work doesn't disappear — decide what it costs.")
                            .font(.system(size: TypeScale.body))
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 28)

                    if !goal.overdueTasks.isEmpty {
                        ThemedCard {
                            Text("What you skipped").labelStyle(palette)
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(goal.overdueTasks.prefix(5)) { task in
                                    HStack(alignment: .top, spacing: 10) {
                                        Text(task.date.formatted(.dateTime.month(.abbreviated).day()))
                                            .font(.system(size: TypeScale.label, weight: .medium))
                                            .foregroundStyle(palette.gridMissed)
                                            .frame(width: 50, alignment: .leading)
                                        Text(task.title)
                                            .font(.system(size: TypeScale.bodySm))
                                            .foregroundStyle(palette.textSecondary)
                                        Spacer()
                                        Text(daysOverdueLabel(task))
                                            .font(.system(size: TypeScale.caption, weight: .semibold))
                                            .foregroundStyle(palette.gridMissed)
                                    }
                                }
                                if goal.overdueTasks.count > 5 {
                                    Text("+ \(goal.overdueTasks.count - 5) more")
                                        .font(.system(size: TypeScale.bodySm, weight: .medium))
                                        .foregroundStyle(palette.textTertiary)
                                }
                            }
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: TypeScale.bodySm))
                            .foregroundStyle(palette.accentSecondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }

            VStack(spacing: 10) {
                if isRecutting {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Recutting the plan…")
                            .bodyStyle(palette, size: TypeScale.bodySm)
                        PlanSkeletonList(palette: palette, rows: 3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Button {
                        recut(keepingDeadline: true)
                    } label: {
                        VStack(spacing: 2) {
                            Text("Keep the deadline")
                                .font(.system(size: TypeScale.body, weight: .semibold))
                            Text("Same date. Heavier days.")
                                .font(.system(size: TypeScale.label))
                                .opacity(0.8)
                        }
                    }
                    .buttonStyle(FilledPillButtonStyle(palette: palette))

                    Button {
                        recut(keepingDeadline: false)
                    } label: {
                        VStack(spacing: 2) {
                            Text("Push the deadline \(goal.missedDayCount) day\(goal.missedDayCount == 1 ? "" : "s")")
                                .font(.system(size: TypeScale.body, weight: .medium))
                            Text("Same pace. Later finish.")
                                .font(.system(size: TypeScale.label))
                                .opacity(0.7)
                        }
                    }
                    .buttonStyle(OutlinePillButtonStyle(palette: palette))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity)
        .screenBackground()
        .interactiveDismissDisabled(isRecutting)
        .onAppear { appeared = true }
    }

    private func recut(keepingDeadline: Bool) {
        isRecutting = true
        errorMessage = nil
        // Captured before anything is destroyed, so a worse plan can be reversed.
        GoalActions.snapshotPlan(goal)

        let cal = Calendar.appDefault
        let newDeadline = keepingDeadline
            ? goal.deadline
            : cal.date(byAdding: .day, value: goal.missedDayCount, to: goal.deadline) ?? goal.deadline

        let unfinished = goal.overdueTasks.map(\.title)
        let remaining = goal.upcomingTasks.map(\.title)

        Task {
            do {
                let drafts = try await ClaudeClient.recutPlan(
                    goalTitle: goal.title,
                    newDeadline: newDeadline,
                    capacity: goal.capacity,
                    missedDayCount: goal.missedDayCount,
                    unfinishedTasks: unfinished,
                    remainingTasks: remaining,
                    keepingDeadline: keepingDeadline
                )
                guard !drafts.isEmpty else {
                    errorMessage = "The recut came back empty. Try again."
                    isRecutting = false
                    return
                }
                apply(drafts, newDeadline: newDeadline)
            } catch {
                errorMessage = error.localizedDescription
                isRecutting = false
            }
        }
    }

    /// Drops everything from today onward (plus the unfinished past) and replaces it with
    /// the recut plan. Completed history is left untouched.
    private func apply(_ drafts: [TaskDraft], newDeadline: Date) {
        let cal = Calendar.appDefault
        let today = cal.startOfDay(for: .now)

        for task in goal.tasks {
            let day = cal.startOfDay(for: task.date)
            if day >= today || (day < today && !task.isDone) {
                context.delete(task)
            }
        }

        for (index, item) in drafts.enumerated() {
            guard let date = item.parsedDate else { continue }
            context.insert(DailyTask(date: date, title: item.title, order: index, goal: goal))
        }

        goal.deadline = newDeadline
        goal.recutCount += 1
        goal.markDirty()
        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()

        isRecutting = false
        dismiss()
    }

    private func daysOverdueLabel(_ task: DailyTask) -> String {
        let cal = Calendar.appDefault
        let days = max(1, cal.dateComponents(
            [.day],
            from: cal.startOfDay(for: task.date),
            to: cal.startOfDay(for: .now)
        ).day ?? 1)
        return days == 1 ? "1d" : "\(days)d"
    }
}
