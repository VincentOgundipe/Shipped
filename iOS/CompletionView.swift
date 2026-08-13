import SwiftUI
import SwiftData
import WidgetKit

/// The ending the app didn't have. Shown once every scheduled task is done: it states what
/// was achieved, then archives the goal so the next one can start clean.
struct CompletionView: View {
    @Bindable var goal: Goal
    @Environment(\.modelContext) private var context
    @Environment(\.themePalette) private var palette

    @State private var revealed = false
    @State private var burstTick = 0

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            StreakFlame(
                level: 4,
                palette: palette,
                size: 78,
                celebrateTrigger: burstTick
            )
            .scaleEffect(revealed ? 1 : 0.4)
            .opacity(revealed ? 1 : 0)
            .animation(.spring(response: 0.6, dampingFraction: 0.55), value: revealed)

            VStack(spacing: 10) {
                Text("Shipped.")
                    .displayStyle(palette, size: TypeScale.display)
                Text(goal.title)
                    .font(.system(size: TypeScale.body))
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 26)
            .padding(.horizontal, 32)
            .staggeredEntrance(index: 2, visible: revealed)

            HStack(spacing: 10) {
                ResultStat(value: "\(goal.tasks.count)", label: "days", palette: palette)
                ResultStat(value: "\(goal.streak)", label: "best streak", palette: palette)
                if goal.daysEarly > 0 {
                    ResultStat(value: "\(goal.daysEarly)", label: "days early", palette: palette)
                } else if goal.recutCount > 0 {
                    ResultStat(value: "\(goal.recutCount)×", label: "recut", palette: palette)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .staggeredEntrance(index: 5, visible: revealed)

            ThemedCard {
                ProgressGridView(
                    cells: GoalGrid.cells(for: goal),
                    palette: palette,
                    columns: 14,
                    spacing: 4,
                    animateOnAppear: true
                )
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .staggeredEntrance(index: 8, visible: revealed)

            Spacer()

            VStack(spacing: 10) {
                Button("Start the next one") { finish() }
                    .buttonStyle(FilledPillButtonStyle(palette: palette))
                Text("This goal moves to your history. Nothing is deleted.")
                    .font(.system(size: TypeScale.label))
                    .foregroundStyle(palette.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 34)
            .staggeredEntrance(index: 11, visible: revealed)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .onAppear {
            revealed = true
            if goal.completedAt == nil {
                goal.completedAt = .now
                goal.markDirty()
                try? context.save()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { burstTick += 1 }
        }
    }

    private func finish() {
        NotificationScheduler.cancelDailyCheckIn()
        NotificationScheduler.cancelBehindNudge()
        GoalActions.archive(goal, in: context, completed: true)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

private struct ResultStat: View {
    let value: String
    let label: String
    let palette: ThemePalette

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: TypeScale.heading, weight: palette.displayWeight))
                .foregroundStyle(palette.accent)
            Text(label)
                .font(.system(size: TypeScale.label))
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: palette.cornerRadius))
    }
}
