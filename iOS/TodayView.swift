import SwiftUI
import SwiftData
import WidgetKit

struct TodayView: View {
    let goals: [Goal]
    var routines: [Routine] = []
    @Environment(\.modelContext) private var context
    @Environment(\.themePalette) private var palette

    private var routinesToday: [Routine] {
        routines.filter { $0.isActive(on: .now) }
    }

    private var activeGoals: [Goal] { goals.filter { !$0.isComplete } }
    private var completedGoals: [Goal] { goals.filter(\.isComplete) }
    /// The behind sheet only makes sense for the single most important thing — showing it
    /// once per goal every time Today appears would be a wall of sheets.
    private var mostUrgentBehindGoal: Goal? { activeGoals.first { $0.isBehind } }

    @State private var showSettings = false
    @State private var showGoalsList = false
    @State private var showPomodoro = false
    @State private var showBehindSheet = false
    @State private var notificationsOff = false
    /// Fires exactly once, at the moment a goal transitions to complete — a permanent
    /// full-screen route based on `isComplete` doesn't work once other goals still need
    /// attention, but the celebratory moment itself is worth keeping.
    @State private var justCompletedGoal: Goal?
    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                if notificationsOff { notificationWarning }
                if !routinesToday.isEmpty {
                    routinesSection.staggeredEntrance(index: 0, visible: appeared)
                }
                ForEach(Array(activeGoals.enumerated()), id: \.element.id) { index, goal in
                    GoalSection(goal: goal, palette: palette, context: context) {
                        justCompletedGoal = goal
                    }
                    .staggeredEntrance(index: index + 1, visible: appeared)
                }
                ForEach(Array(completedGoals.enumerated()), id: \.element.id) { index, goal in
                    CompletedGoalCard(goal: goal, palette: palette) {
                        withAnimation(Motion.settle) {
                            GoalActions.archive(goal, in: context, completed: true)
                        }
                    }
                    .staggeredEntrance(index: activeGoals.count + index + 1, visible: appeared)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if goals.count == 1 { showSettings = true } else { showGoalsList = true }
                } label: {
                    Image(systemName: "gearshape")
                        .foregroundStyle(palette.text)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showPomodoro = true
                } label: {
                    Image(systemName: "timer")
                        .foregroundStyle(palette.text)
                }
            }
        }
        .sheet(isPresented: $showPomodoro) {
            PomodoroView()
                .environment(\.themePalette, palette)
        }
        .sheet(isPresented: $showSettings) {
            if let only = goals.first {
                SettingsView(goal: only)
                    .environment(\.themePalette, palette)
            }
        }
        .sheet(isPresented: $showGoalsList) {
            GoalsListView(goals: goals)
                .environment(\.themePalette, palette)
        }
        .sheet(isPresented: $showBehindSheet) {
            if let goal = mostUrgentBehindGoal {
                BehindSheet(goal: goal)
                    .environment(\.themePalette, palette)
            }
        }
        .fullScreenCover(item: $justCompletedGoal) { goal in
            CompletionView(goal: goal)
                .environment(\.themePalette, palette)
        }
        .onAppear {
            appeared = true
            if mostUrgentBehindGoal != nil { showBehindSheet = true }
            Task {
                notificationsOff = !(await NotificationScheduler.refreshAuthorization())
                if let goal = mostUrgentBehindGoal {
                    await NotificationScheduler.scheduleBehindNudge(
                        missedDays: goal.missedDayCount,
                        goalTitle: goal.title
                    )
                } else {
                    NotificationScheduler.cancelBehindNudge()
                }
            }
        }
    }

    /// Says plainly that the daily check-in can't arrive, rather than pretending it will.
    private var notificationWarning: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "bell.slash.fill")
                .font(.system(size: TypeScale.bodySm))
                .foregroundStyle(palette.accentSecondary)
            VStack(alignment: .leading, spacing: 3) {
                Text("Daily check-in is off")
                    .font(.system(size: TypeScale.bodySm, weight: .semibold))
                    .foregroundStyle(palette.text)
                Text("Notifications are blocked, so nothing will remind you. Turn them on in Settings › Shipped.")
                    .font(.system(size: TypeScale.label))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: palette.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: palette.cornerRadius)
                .stroke(palette.accentSecondary.opacity(0.45), lineWidth: 1)
        )
    }

    // MARK: - Routines

    private var routinesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Routines").labelStyle(palette)
            VStack(spacing: 10) {
                ForEach(routinesToday) { routine in
                    RoutineRow(routine: routine, palette: palette) {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) {
                            RoutineActions.toggleToday(routine, in: context)
                        }
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                }
            }
        }
    }
}

// MARK: - One goal's section

/// Everything for a single active goal — header, grid, today, coming up. Today shows one of
/// these per active goal, top priority first, rather than picking just one to display.
private struct GoalSection: View {
    @Bindable var goal: Goal
    let palette: ThemePalette
    let context: ModelContext
    var onComplete: () -> Void

    @AppStorage(AppSettings.focusModeKey, store: AppSettings.defaults)
    private var focusMode = false

    @State private var celebrating = false
    @State private var celebrationTick = 0
    @State private var showRestConfirm = false
    @State private var showAddTask = false
    @State private var newTaskTitle = ""
    @FocusState private var addTaskFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            gridCard
            todaySection
            if !focusMode && !goal.upcomingUnfinishedTasks.isEmpty {
                comingUpSection
            }
        }
        .padding(16)
        .background(palette.surface.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: palette.cornerRadius))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: -4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(headlineNumber)")
                            .font(.system(size: 44, weight: palette.displayWeight))
                            .tracking(-1.5)
                            .foregroundStyle(goal.isBehind ? palette.accentSecondary : palette.text)
                            .contentTransition(.numericText())
                        Text(headlineUnit)
                            .font(.system(size: TypeScale.body))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                Spacer()
                StreakBadge(goal: goal, palette: palette, celebrateTrigger: celebrationTick)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(statusHeadline)
                    .displayStyle(palette, size: TypeScale.headingSm)
                    .fixedSize(horizontal: false, vertical: true)
                Text(goal.title)
                    .bodyStyle(palette, size: TypeScale.bodySm)
            }
        }
    }

    private var headlineNumber: Int {
        goal.isBehind ? goal.missedDayCount : goal.daysRemaining
    }

    private var headlineUnit: String {
        if goal.isBehind {
            return goal.missedDayCount == 1 ? "day missed" : "days missed"
        }
        return goal.daysRemaining == 1 ? "day left" : "days left"
    }

    private var statusHeadline: String {
        if goal.isBehind { return "You fell behind." }
        if goal.isDoneForToday { return "Done for today." }
        if goal.todaysTasks.isEmpty { return "Nothing scheduled." }
        return "Here's today."
    }

    private var gridCard: some View {
        ThemedCard {
            HStack {
                Text("Progress").labelStyle(palette)
                Spacer()
                Text("\(Int(goal.progress * 100))%")
                    .font(.system(size: TypeScale.bodySm, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .contentTransition(.numericText())
            }

            ProgressGridView(
                cells: GoalGrid.cells(for: goal),
                palette: palette,
                columns: 14,
                spacing: 4,
                animateOnAppear: true
            )

            if !focusMode {
                HStack(spacing: 14) {
                    LegendDot(color: palette.gridDone, label: "shipped", palette: palette)
                    LegendDot(color: palette.gridMissed, label: "missed", palette: palette)
                    Spacer()
                    if goal.deadlineWasPushed {
                        Text("deadline pushed")
                            .font(.system(size: TypeScale.label, weight: .medium))
                            .foregroundStyle(palette.accentSecondary)
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today").labelStyle(palette)

            if goal.todaysTasks.isEmpty {
                Text("No task scheduled today. Rest day, or add one from the plan.")
                    .bodyStyle(palette)
            } else {
                VStack(spacing: 10) {
                    ForEach(goal.todaysTasks) { task in
                        TaskRow(task: task, palette: palette) { toggle(task) }
                    }
                }
            }

            inlineAddRow

            if goal.isRestDayToday {
                HStack(spacing: 8) {
                    Image(systemName: "moon.zzz.fill")
                        .foregroundStyle(palette.accentSecondary)
                    Text("Rest day. Your streak is safe.")
                        .font(.system(size: TypeScale.bodySm, weight: .semibold))
                        .foregroundStyle(palette.text)
                    Spacer()
                    Button("Undo") {
                        GoalActions.undoRestDay(goal, in: context)
                    }
                    .font(.system(size: TypeScale.label, weight: .medium))
                    .foregroundStyle(palette.accent)
                }
                .padding(.top, 2)
            } else if !goal.isDoneForToday && !goal.todaysTasks.isEmpty {
                Button {
                    showRestConfirm = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "moon.zzz")
                            .font(.system(size: TypeScale.label))
                        Text("Take a rest day")
                            .font(.system(size: TypeScale.label, weight: .medium))
                    }
                    .foregroundStyle(palette.textSecondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
                .confirmationDialog(
                    "Take a rest day?",
                    isPresented: $showRestConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Rest today") {
                        withAnimation(Motion.settle) {
                            GoalActions.takeRestDay(goal, in: context)
                        }
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Your streak survives, and today's work moves to tomorrow. It isn't forgiven, just deferred.")
                }
            }

            if goal.isDoneForToday {
                HStack(spacing: 8) {
                    StreakFlame(
                        level: goal.intensity,
                        palette: palette,
                        size: 26,
                        celebrateTrigger: celebrationTick
                    )
                    Text(celebrationLine)
                        .font(.system(size: TypeScale.bodySm, weight: .semibold))
                        .foregroundStyle(palette.text)
                }
                .padding(.top, 2)
                .scaleEffect(celebrating ? 1.06 : 1)
                .animation(.spring(response: 0.35, dampingFraction: 0.5), value: celebrating)
            }
        }
    }

    private var comingUpSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Coming up").labelStyle(palette)
                Spacer()
                if goal.daysBanked > 0 {
                    Text("\(goal.daysBanked) already banked")
                        .font(.system(size: TypeScale.caption, weight: .medium))
                        .foregroundStyle(palette.accentSecondary)
                } else {
                    Text("tick ahead to bank days")
                        .font(.system(size: TypeScale.caption))
                        .foregroundStyle(palette.textTertiary)
                }
            }

            VStack(spacing: 0) {
                let upcoming = Array(goal.upcomingUnfinishedTasks.prefix(7))
                ForEach(Array(upcoming.enumerated()), id: \.element.id) { index, task in
                    Button {
                        toggle(task)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: TypeScale.body))
                                .foregroundStyle(task.isDone ? palette.accentSecondary : palette.textTertiary)
                                .padding(.top, 1)
                            Text(task.date.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.system(size: TypeScale.label, weight: .medium))
                                .foregroundStyle(palette.textTertiary)
                                .frame(width: 46, alignment: .leading)
                                .padding(.top, 2)
                            Text(task.title)
                                .font(.system(size: TypeScale.body))
                                .foregroundStyle(task.isDone ? palette.textTertiary : palette.textSecondary)
                                .strikethrough(task.isDone, color: palette.textTertiary)
                                .multilineTextAlignment(.leading)
                            Spacer()
                        }
                        .padding(.vertical, 11)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < upcoming.count - 1 { HairlineDivider() }
                }
            }
        }
    }

    private var celebrationLine: String {
        if goal.daysBanked > 0 {
            return "\(goal.daysBanked) day\(goal.daysBanked == 1 ? "" : "s") banked ahead."
        }
        if goal.streak > 1 { return "\(goal.streak) days in a row." }
        return "First one down."
    }

    // MARK: - Inline add

    private var inlineAddRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showAddTask {
                HStack(spacing: 10) {
                    TextField("Add a task for today", text: $newTaskTitle)
                        .font(.system(size: TypeScale.bodySm))
                        .focused($addTaskFocused)
                        .submitLabel(.done)
                        .onSubmit(commitNewTask)
                    Button("Add", action: commitNewTask)
                        .font(.system(size: TypeScale.bodySm, weight: .semibold))
                        .foregroundStyle(palette.accent)
                        .disabled(newTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(12)
                .background(palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: palette.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: palette.cornerRadius)
                        .stroke(palette.accent, lineWidth: 1)
                )
            } else {
                Button {
                    withAnimation(Motion.snappy) { showAddTask = true }
                    addTaskFocused = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle")
                        Text("Add a task")
                    }
                    .font(.system(size: TypeScale.label, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 2)
    }

    private func commitNewTask() {
        guard GoalActions.addTask(newTaskTitle, to: goal, in: context) != nil else { return }
        newTaskTitle = ""
        showAddTask = false
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func toggle(_ task: DailyTask) {
        let wasComplete = goal.isComplete
        let becomingDone = !task.isDone
        withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) {
            task.isDone.toggle()
        }
        task.markDirty()
        if becomingDone { celebrationTick += 1 }
        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()

        if !wasComplete && goal.isComplete {
            onComplete()
        }

        if goal.isDoneForToday {
            celebrating = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { celebrating = false }
        }
    }
}

/// A finished goal, shown inline rather than as a full-screen takeover — with multiple goals
/// running at once, one finishing shouldn't block seeing what's still active.
private struct CompletedGoalCard: View {
    let goal: Goal
    let palette: ThemePalette
    var onArchive: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            StreakFlame(level: 4, palette: palette, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(goal.title)
                    .font(.system(size: TypeScale.body, weight: .semibold))
                    .foregroundStyle(palette.text)
                Text(goal.daysEarly > 0 ? "Shipped \(goal.daysEarly) days early." : "Shipped.")
                    .font(.system(size: TypeScale.bodySm))
                    .foregroundStyle(palette.textSecondary)
            }
            Spacer()
            Button("Archive", action: onArchive)
                .buttonStyle(OutlinePillButtonStyle(palette: palette))
        }
        .padding(16)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: palette.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: palette.cornerRadius)
                .stroke(palette.accent.opacity(0.35), lineWidth: 1)
        )
    }
}

// MARK: - Pieces

private struct TaskRow: View {
    let task: DailyTask
    let palette: ThemePalette
    var onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.small)
                        .stroke(task.isDone ? palette.accent : palette.border, lineWidth: 2)
                        .frame(width: 24, height: 24)
                    if task.isDone {
                        RoundedRectangle(cornerRadius: Radius.small)
                            .fill(palette.accent)
                            .frame(width: 24, height: 24)
                        Image(systemName: "checkmark")
                            .font(.system(size: TypeScale.bodySm, weight: .bold))
                            .foregroundStyle(palette.onAccent)
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: task.isDone)

                Text(task.title)
                    .font(.system(size: TypeScale.body, weight: .medium))
                    .foregroundStyle(task.isDone ? palette.textTertiary : palette.text)
                    .strikethrough(task.isDone, color: palette.textTertiary)
                    .multilineTextAlignment(.leading)
                Spacer()
            }
            .padding(16)
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: palette.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: palette.cornerRadius)
                    .stroke(task.isDone ? palette.accent.opacity(0.4) : palette.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct RoutineRow: View {
    let routine: Routine
    let palette: ThemePalette
    var onToggle: () -> Void

    var body: some View {
        let activity = routine.activity(for: .now)
        let done = routine.isDone(on: .now)
        Button(action: onToggle) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.small)
                        .stroke(done ? palette.accent : palette.border, lineWidth: 2)
                        .frame(width: 24, height: 24)
                    if done {
                        RoundedRectangle(cornerRadius: Radius.small)
                            .fill(palette.accent)
                            .frame(width: 24, height: 24)
                        Image(systemName: "checkmark")
                            .font(.system(size: TypeScale.bodySm, weight: .bold))
                            .foregroundStyle(palette.onAccent)
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: done)

                VStack(alignment: .leading, spacing: 2) {
                    Text(activity?.title ?? routine.title)
                        .font(.system(size: TypeScale.body, weight: .medium))
                        .foregroundStyle(done ? palette.textTertiary : palette.text)
                        .strikethrough(done, color: palette.textTertiary)
                    Text(routine.title)
                        .font(.system(size: TypeScale.caption))
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer()
                if routine.streak > 0 {
                    Text("\(routine.streak)")
                        .font(.system(size: TypeScale.label, weight: .semibold))
                        .foregroundStyle(palette.accentSecondary)
                }
            }
            .padding(16)
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: palette.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: palette.cornerRadius)
                    .stroke(done ? palette.accent.opacity(0.4) : palette.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct LegendDot: View {
    let color: Color
    let label: String
    let palette: ThemePalette

    var body: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 9, height: 9)
            Text(label)
                .font(.system(size: TypeScale.label))
                .foregroundStyle(palette.textTertiary)
        }
    }
}

/// Streak, banked days, and intensity in one corner block. The thing the user should not
/// want to lose.
struct StreakBadge: View {
    let goal: Goal
    let palette: ThemePalette
    var celebrateTrigger: Int = 0

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 7) {
                Text(goal.intensityLabel)
                    .font(.system(size: TypeScale.label, weight: .semibold))
                    .tracking(0.5)
                    .textCase(.uppercase)
                    .foregroundStyle(goal.intensity > 0 ? palette.accent : palette.textTertiary)
                StreakFlame(
                    level: goal.intensity,
                    palette: palette,
                    size: 28,
                    celebrateTrigger: celebrateTrigger
                )
            }

            HStack(spacing: 4) {
                if goal.streak > 0 {
                    MetricChip(value: "\(goal.streak)", unit: "streak", palette: palette, emphasised: false)
                }
                if goal.daysBanked > 0 {
                    MetricChip(value: "+\(goal.daysBanked)", unit: "banked", palette: palette, emphasised: true)
                }
            }
        }
    }
}

private struct MetricChip: View {
    let value: String
    let unit: String
    let palette: ThemePalette
    let emphasised: Bool

    var body: some View {
        HStack(spacing: 3) {
            Text(value)
                .font(.system(size: TypeScale.label, weight: .bold))
                .contentTransition(.numericText())
            Text(unit)
                .font(.system(size: TypeScale.caption))
        }
        .foregroundStyle(emphasised ? palette.onAccent : palette.textSecondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(emphasised ? palette.accentSecondary : palette.surface)
        .clipShape(Capsule())
    }
}
