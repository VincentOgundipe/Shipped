import SwiftUI
import SwiftData

/// Custom sidebar + detail. Deliberately not `NavigationSplitView`'s default sidebar: that
/// styling ignores the app's palette and type scale, which made the Mac window read as a
/// wireframe next to the phone.
struct MacRootView: View {
    @Query(
        filter: #Predicate<Goal> { !$0.isArchived },
        sort: \Goal.priorityRank
    ) private var goals: [Goal]
    @Query(
        filter: #Predicate<Routine> { !$0.isArchived },
        sort: \Routine.createdAt,
        order: .reverse
    ) private var routines: [Routine]
    @Environment(\.themePalette) private var palette

    @AppStorage(AppSettings.themeModeKey, store: AppSettings.defaults)
    private var themeModeRaw = ThemeMode.light.rawValue

    @AppStorage("macSidebarCollapsed", store: AppSettings.defaults)
    private var sidebarCollapsed = false

    @State private var section: MacSection = .today
    @State private var selectedGoalID: PersistentIdentifier?
    @State private var transition = ThemeTransition()
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    /// The goal Plan/Progress focus on — whichever was last picked, falling back to top
    /// priority. Today shows every goal at once, but those two tabs are single-goal views.
    private var selectedGoal: Goal? {
        (selectedGoalID.flatMap { id in goals.first { $0.persistentModelID == id } }) ?? goals.first
    }

    private var goal: Goal? { goals.first }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle()
                .fill(palette.border)
                .frame(width: 1)
            detail
        }
        .background(palette.background)
        .themeReveal(transition)
        // Same reasoning as the iOS side: sync on launch and whenever the window comes back
        // to the foreground, silently — a manual button alone means the two devices only
        // line up when you remember to press it.
        .task { await trySync() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await trySync() } }
        }
        // ⌘\ is the system-standard sidebar toggle on macOS.
        .background {
            Button("") { toggleSidebar() }
                .keyboardShortcut("\\", modifiers: .command)
                .opacity(0)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                MacMark(palette: palette)
                    .frame(width: 22, height: 22)
                if !sidebarCollapsed {
                    Text("Shipped")
                        .font(.system(size: TypeScale.body, weight: .semibold))
                        .foregroundStyle(palette.text)
                }
            }
            .padding(.horizontal, sidebarCollapsed ? 17 : 18)
            .padding(.top, 22)
            .padding(.bottom, 20)

            VStack(spacing: 2) {
                ForEach(MacSection.allCases) { candidate in
                    SidebarRow(
                        section: candidate,
                        isSelected: section == candidate,
                        collapsed: sidebarCollapsed,
                        palette: palette
                    ) {
                        withAnimation(Motion.snappy) { section = candidate }
                    }
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            if let goal {
                VStack(alignment: .leading, spacing: 8) {
                    Rectangle().fill(palette.border).frame(height: 1)
                    HStack(spacing: 8) {
                        StreakFlame(level: goal.intensity, palette: palette, size: 20)
                        if !sidebarCollapsed {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(goal.intensityLabel)
                                    .font(.system(size: TypeScale.caption, weight: .bold))
                                    .tracking(0.5)
                                    .textCase(.uppercase)
                                    .foregroundStyle(palette.accent)
                                Text(goal.runSummary)
                                    .font(.system(size: TypeScale.caption))
                                    .foregroundStyle(palette.textTertiary)
                            }
                        }
                    }
                    .padding(.horizontal, sidebarCollapsed ? 18 : 18)
                    .padding(.bottom, 6)
                }
            }

            Button {
                let next: ThemeMode = (ThemeMode(storedValue: themeModeRaw) ?? .light) == .light
                    ? .lockedIn : .light
                transition.run(to: next, from: .leadingEdge) {
                    themeModeRaw = next.rawValue
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: palette.isDark ? "sun.max" : "moon")
                        .font(.system(size: TypeScale.bodySm))
                        .frame(width: 18)
                    if !sidebarCollapsed {
                        Text(palette.isDark ? "Light" : "Locked In")
                            .font(.system(size: TypeScale.bodySm, weight: .medium))
                        Spacer()
                    }
                }
                .foregroundStyle(palette.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.bottom, 14)
        }
        .frame(width: sidebarCollapsed ? 56 : 216)
        .background(palette.surface)
        .overlay(alignment: .topTrailing) {
            if !sidebarCollapsed {
                Button(action: toggleSidebar) {
                    Image(systemName: "sidebar.leading")
                        .font(.system(size: TypeScale.bodySm))
                        .foregroundStyle(palette.textSecondary)
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Hide sidebar (⌘\\)")
                .padding(.top, 20)
                .padding(.trailing, 10)
            }
        }
    }

    private func trySync() async {
        guard SyncCoordinator.isConfigured else { return }
        try? await SyncCoordinator.sync(in: context)
    }

    private var goalPicker: some View {
        Picker("Goal", selection: Binding(
            get: { selectedGoal?.persistentModelID },
            set: { selectedGoalID = $0 }
        )) {
            ForEach(goals) { goal in
                Text(goal.title).tag(Optional(goal.persistentModelID))
            }
        }
        .labelsHidden()
        .padding(.horizontal, 34)
        .padding(.top, 24)
        .padding(.bottom, 4)
    }

    private func toggleSidebar() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            sidebarCollapsed.toggle()
        }
    }

    // MARK: - Detail

    private var detail: some View {
        Group {
            switch section {
            case .capture:
                CapturePane(goal: goal)
            case .coach:
                CoachPane(goal: goal)
            case .routines:
                MacRoutinesPane(routines: routines) { withAnimation { section = .capture } }
            case .today:
                if !goals.isEmpty || !routines.isEmpty {
                    MacTodayPane(goals: goals, routines: routines)
                } else {
                    MacEmptyState { withAnimation { section = .capture } }
                }
            case .plan, .grid:
                if let selectedGoal {
                    VStack(alignment: .leading, spacing: 0) {
                        if goals.count > 1 { goalPicker }
                        switch section {
                        case .plan: MacPlanPane(goal: selectedGoal)
                        default: MacGridPane(goal: selectedGoal)
                        }
                    }
                } else {
                    MacEmptyState { withAnimation { section = .capture } }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.background)
        .overlay(alignment: .topLeading) {
            if sidebarCollapsed {
                Button(action: toggleSidebar) {
                    Image(systemName: "sidebar.leading")
                        .font(.system(size: TypeScale.bodySm))
                        .foregroundStyle(palette.textSecondary)
                        .padding(8)
                        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.small))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Show sidebar (⌘\\)")
                .padding(.leading, 14)
                .padding(.top, 14)
            }
        }
    }
}

// MARK: - Sidebar pieces

private struct SidebarRow: View {
    let section: MacSection
    let isSelected: Bool
    let collapsed: Bool
    let palette: ThemePalette
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.symbol)
                    .font(.system(size: TypeScale.bodySm, weight: .medium))
                    .frame(width: 18)
                if !collapsed {
                    Text(section.title)
                        .font(.system(size: TypeScale.bodySm, weight: isSelected ? .semibold : .regular))
                    Spacer()
                }
            }
            .foregroundStyle(isSelected ? palette.text : palette.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: Radius.small)
                    .fill(isSelected ? palette.surfaceRaised
                          : (hovering ? palette.surfaceRaised.opacity(0.6) : .clear))
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule()
                        .fill(palette.accent)
                        .frame(width: 2.5, height: 15)
                        .offset(x: 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(collapsed ? section.title : "")
    }
}

/// The app mark, small — same 4×4 grid as the icon.
private struct MacMark: View {
    let palette: ThemePalette
    private let filled: Set<Int> = [0, 1, 2, 4, 5, 6, 8, 9]

    var body: some View {
        VStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(0..<4, id: \.self) { column in
                        let index = row * 4 + column
                        RoundedRectangle(cornerRadius: 1)
                            .fill(filled.contains(index) ? palette.accent
                                  : index == 10 ? palette.accentSecondary
                                  : palette.border)
                    }
                }
            }
        }
    }
}

enum MacSection: String, CaseIterable, Identifiable {
    case today
    case plan
    case grid
    case routines
    case capture
    case coach

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .plan: return "Plan"
        case .grid: return "Progress"
        case .routines: return "Routines"
        case .capture: return "Capture"
        case .coach: return "Coach"
        }
    }

    var symbol: String {
        switch self {
        case .today: return "checkmark.circle"
        case .plan: return "calendar"
        case .grid: return "square.grid.3x3"
        case .routines: return "repeat"
        case .capture: return "square.and.pencil"
        case .coach: return "bubble.left.and.bubble.right"
        }
    }
}

// MARK: - Today

private struct MacTodayPane: View {
    let goals: [Goal]
    let routines: [Routine]
    @Environment(\.modelContext) private var context
    @Environment(\.themePalette) private var palette
    @EnvironmentObject private var status: CheckInStatus

    @AppStorage(AppSettings.focusModeKey, store: AppSettings.defaults)
    private var focusMode = false

    @State private var celebrationTick = 0
    @State private var justCompletedGoal: Goal?

    private var routinesToday: [Routine] {
        routines.filter { $0.isActive(on: .now) }
    }
    private var activeGoals: [Goal] { goals.filter { !$0.isComplete } }
    private var completedGoals: [Goal] { goals.filter(\.isComplete) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if !routinesToday.isEmpty { routinesBlock }
                ForEach(activeGoals) { goal in
                    VStack(alignment: .leading, spacing: 20) {
                        header(for: goal)
                        grid(for: goal)
                        todayBlock(for: goal)
                        if !focusMode && !goal.upcomingUnfinishedTasks.isEmpty { comingUp(for: goal) }
                    }
                    .padding(18)
                    .background(palette.surfaceRaised.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: palette.cornerRadius))
                }
                ForEach(completedGoals) { goal in
                    MacCompletedGoalCard(goal: goal, palette: palette) {
                        GoalActions.archive(goal, in: context, completed: true)
                    }
                }
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 30)
            .frame(maxWidth: 780, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .sheet(item: $justCompletedGoal) { goal in
            MacCompletionView(goal: goal) {
                GoalActions.archive(goal, in: context, completed: true)
                justCompletedGoal = nil
            }
            .environment(\.themePalette, palette)
        }
    }

    private var routinesBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Routines").labelStyle(palette)
            VStack(spacing: 8) {
                ForEach(routinesToday) { routine in
                    MacRoutineRow(routine: routine, palette: palette) {
                        withAnimation(Motion.snappy) {
                            RoutineActions.toggleToday(routine, in: context)
                        }
                    }
                }
            }
        }
    }

    private func header(for goal: Goal) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text("\(goal.isBehind ? goal.missedDayCount : goal.daysRemaining)")
                        .font(.system(size: 62, weight: palette.displayWeight))
                        .tracking(-2)
                        .foregroundStyle(goal.isBehind ? palette.accentSecondary : palette.text)
                        .contentTransition(.numericText())
                    Text(goal.isBehind ? "days missed" : "days left")
                        .font(.system(size: TypeScale.bodyLg))
                        .foregroundStyle(palette.textSecondary)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(statusHeadline(for: goal))
                        .displayStyle(palette, size: TypeScale.headingSm)
                    Text(goal.title)
                        .bodyStyle(palette, size: TypeScale.bodySm)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) {
                    Text(goal.intensityLabel)
                        .font(.system(size: TypeScale.label, weight: .semibold))
                        .tracking(0.5)
                        .textCase(.uppercase)
                        .foregroundStyle(goal.intensity > 0 ? palette.accent : palette.textTertiary)
                    StreakFlame(
                        level: goal.intensity,
                        palette: palette,
                        size: 26,
                        celebrateTrigger: celebrationTick
                    )
                }
                Text(goal.runSummary)
                    .font(.system(size: TypeScale.label, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
            }
        }
    }

    private func statusHeadline(for goal: Goal) -> String {
        if goal.isBehind { return "You fell behind." }
        if goal.isDoneForToday { return "Done for today." }
        if goal.todaysTasks.isEmpty { return "Nothing scheduled." }
        return "Here's today."
    }

    private func grid(for goal: Goal) -> some View {
        ThemedCard(padding: 22) {
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
                columns: 24,
                spacing: 4,
                cornerRadius: 3,
                animateOnAppear: true
            )
        }
    }

    private func todayBlock(for goal: Goal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Today").labelStyle(palette)
            if goal.todaysTasks.isEmpty {
                Text("No task scheduled today. Rest day, or pull something forward.")
                    .bodyStyle(palette, size: TypeScale.bodySm)
            } else {
                VStack(spacing: 8) {
                    ForEach(goal.todaysTasks) { task in
                        MacTaskRow(task: task, palette: palette) { toggle(task) }
                    }
                }
            }
        }
    }

    private func comingUp(for goal: Goal) -> some View {
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
                let upcoming = Array(goal.upcomingUnfinishedTasks.prefix(8))
                ForEach(Array(upcoming.enumerated()), id: \.element.id) { index, task in
                    Button { toggle(task) } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: TypeScale.bodySm))
                                .foregroundStyle(task.isDone ? palette.accentSecondary : palette.textTertiary)
                            Text(task.date.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.system(size: TypeScale.label, weight: .medium))
                                .foregroundStyle(palette.textTertiary)
                                .frame(width: 52, alignment: .leading)
                            Text(task.title)
                                .font(.system(size: TypeScale.bodySm))
                                .foregroundStyle(palette.textSecondary)
                            Spacer()
                        }
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if index < upcoming.count - 1 { HairlineDivider() }
                }
            }
        }
    }

    private func toggle(_ task: DailyTask) {
        let wasComplete = task.goal?.isComplete ?? false
        let becomingDone = !task.isDone
        withAnimation(Motion.snappy) { task.isDone.toggle() }
        task.markDirty()
        if becomingDone { celebrationTick += 1 }
        try? context.save()
        status.refresh()

        if let goal = task.goal, !wasComplete && goal.isComplete {
            justCompletedGoal = goal
        }
    }
}

/// A finished goal, shown inline rather than blocking the pane — with multiple goals running
/// at once, one finishing shouldn't hide the others still active.
private struct MacCompletedGoalCard: View {
    let goal: Goal
    let palette: ThemePalette
    var onArchive: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            StreakFlame(level: 4, palette: palette, size: 26)
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

/// The one-time celebration shown the moment a goal transitions to complete — a sheet rather
/// than iOS's full-screen takeover, since the Mac window still has a sidebar to get back to.
private struct MacCompletionView: View {
    let goal: Goal
    let palette: ThemePalette
    var onDone: () -> Void

    init(goal: Goal, onDone: @escaping () -> Void) {
        self.goal = goal
        self.onDone = onDone
        self.palette = Theme.palette(for: ThemeMode(
            storedValue: AppSettings.defaults.string(forKey: AppSettings.themeModeKey)
        ) ?? .light)
    }

    var body: some View {
        VStack(spacing: 20) {
            StreakFlame(level: 4, palette: palette, size: 56)
            VStack(spacing: 8) {
                Text("Shipped.")
                    .displayStyle(palette, size: TypeScale.heading)
                Text(goal.title)
                    .bodyStyle(palette, size: TypeScale.bodySm)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 10) {
                MacStat(value: "\(goal.tasks.count)", label: "days", palette: palette)
                MacStat(value: "\(goal.streak)", label: "best streak", palette: palette)
                if goal.daysEarly > 0 {
                    MacStat(value: "\(goal.daysEarly)", label: "days early", palette: palette)
                }
            }
            Button("Start the next one", action: onDone)
                .buttonStyle(FilledPillButtonStyle(palette: palette, isDisabled: false))
        }
        .padding(32)
        .frame(width: 420)
        .background(palette.background)
    }
}

private struct MacTaskRow: View {
    let task: DailyTask
    let palette: ThemePalette
    var onToggle: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.small)
                        .stroke(task.isDone ? palette.accent : palette.border, lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if task.isDone {
                        RoundedRectangle(cornerRadius: Radius.small)
                            .fill(palette.accent)
                            .frame(width: 22, height: 22)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(palette.onAccent)
                    }
                }
                .animation(Motion.snappy, value: task.isDone)

                Text(task.title)
                    .font(.system(size: TypeScale.body, weight: .medium))
                    .foregroundStyle(task.isDone ? palette.textTertiary : palette.text)
                    .strikethrough(task.isDone, color: palette.textTertiary)
                    .multilineTextAlignment(.leading)
                Spacer()
            }
            .padding(16)
            .background(hovering ? palette.surfaceRaised : palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: palette.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: palette.cornerRadius)
                    .stroke(task.isDone ? palette.accent.opacity(0.35) : palette.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Plan

private struct MacPlanPane: View {
    @Bindable var goal: Goal
    @Environment(\.modelContext) private var context
    @Environment(\.themePalette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("The whole plan").labelStyle(palette)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(goal.tasks.count)")
                            .font(.system(size: 44, weight: palette.displayWeight))
                            .foregroundStyle(palette.accent)
                        Text("days")
                            .displayStyle(palette, size: TypeScale.headingSm)
                        Spacer()
                        Text("\(goal.tasks.filter(\.isDone).count) done")
                            .font(.system(size: TypeScale.bodySm, weight: .medium))
                            .foregroundStyle(palette.textSecondary)
                    }
                }

                ThemedCard(padding: 8) {
                    let sorted = goal.tasks.sorted { $0.date < $1.date }
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { index, task in
                        Button {
                            withAnimation(Motion.snappy) { task.isDone.toggle() }
                        task.markDirty()
                            try? context.save()
                        } label: {
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: TypeScale.bodySm))
                                    .foregroundStyle(task.isDone ? palette.accent : palette.textTertiary)
                                Text(task.date.formatted(.dateTime.month(.abbreviated).day()))
                                    .font(.system(size: TypeScale.label, weight: .medium))
                                    .foregroundStyle(palette.textTertiary)
                                    .frame(width: 54, alignment: .leading)
                                Text(task.title)
                                    .font(.system(size: TypeScale.bodySm))
                                    .foregroundStyle(task.isDone ? palette.textTertiary : palette.text)
                                    .strikethrough(task.isDone, color: palette.textTertiary)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if index < sorted.count - 1 { HairlineDivider() }
                    }
                }
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 30)
            .frame(maxWidth: 780, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

// MARK: - Progress

private struct MacGridPane: View {
    @Bindable var goal: Goal
    @Environment(\.themePalette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Progress").labelStyle(palette)
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text("\(Int(goal.progress * 100))%")
                            .font(.system(size: 62, weight: palette.displayWeight))
                            .tracking(-2)
                            .foregroundStyle(palette.text)
                        Text("shipped")
                            .font(.system(size: TypeScale.bodyLg))
                            .foregroundStyle(palette.textSecondary)
                    }
                }

                ThemedCard(padding: 22) {
                    ProgressGridView(
                        cells: GoalGrid.cells(for: goal),
                        palette: palette,
                        columns: 21,
                        spacing: 6,
                        cornerRadius: 4,
                        animateOnAppear: true
                    )
                    HStack(spacing: 18) {
                        MacLegend(color: palette.gridDone, label: "shipped", palette: palette)
                        MacLegend(color: palette.gridMissed, label: "missed", palette: palette)
                        MacLegend(color: palette.gridFuture, label: "ahead", palette: palette)
                        Spacer()
                    }
                    .padding(.top, 4)
                }

                HStack(spacing: 12) {
                    MacStat(value: "\(goal.streak)", label: "day streak", palette: palette)
                    MacStat(value: "\(goal.daysBanked)", label: "banked", palette: palette)
                    MacStat(value: "\(goal.missedDayCount)", label: "missed", palette: palette)
                    MacStat(value: "\(goal.daysRemaining)", label: "days left", palette: palette)
                }
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 30)
            .frame(maxWidth: 780, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct MacStat: View {
    let value: String
    let label: String
    let palette: ThemePalette

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: TypeScale.heading, weight: palette.displayWeight))
                .foregroundStyle(palette.text)
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: TypeScale.label))
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: palette.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: palette.cornerRadius)
                .stroke(palette.border, lineWidth: 1)
        )
    }
}

private struct MacLegend: View {
    let color: Color
    let label: String
    let palette: ThemePalette

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(label)
                .font(.system(size: TypeScale.label))
                .foregroundStyle(palette.textTertiary)
        }
    }
}

// MARK: - Empty

private struct MacEmptyState: View {
    @Environment(\.themePalette) private var palette
    var onCapture: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            MacMark(palette: palette)
                .frame(width: 46, height: 46)
            Text("No goal yet")
                .displayStyle(palette, size: TypeScale.heading)
            Text("Paste a brain dump into Capture and it'll become a plan, or start one on your iPhone.")
                .bodyStyle(palette, size: TypeScale.bodySm)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button("Open Capture", action: onCapture)
                .buttonStyle(OutlinePillButtonStyle(palette: palette))
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Routines

private struct MacRoutineRow: View {
    let routine: Routine
    let palette: ThemePalette
    var onToggle: () -> Void

    @State private var hovering = false

    var body: some View {
        let activity = routine.activity(for: .now)
        let done = routine.isDone(on: .now)
        Button(action: onToggle) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.small)
                        .stroke(done ? palette.accent : palette.border, lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if done {
                        RoundedRectangle(cornerRadius: Radius.small)
                            .fill(palette.accent)
                            .frame(width: 22, height: 22)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(palette.onAccent)
                    }
                }
                .animation(Motion.snappy, value: done)

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
            .background(hovering ? palette.surfaceRaised : palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: palette.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: palette.cornerRadius)
                    .stroke(done ? palette.accent.opacity(0.35) : palette.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct MacRoutinesPane: View {
    let routines: [Routine]
    var onNewRoutine: () -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.themePalette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("Routines").displayStyle(palette, size: TypeScale.heading)
                    Spacer()
                    Button("New routine", action: onNewRoutine)
                        .buttonStyle(OutlinePillButtonStyle(palette: palette))
                }

                if routines.isEmpty {
                    Text("Nothing recurring yet. A routine runs on repeat with no deadline — a workout split, a daily habit.")
                        .bodyStyle(palette, size: TypeScale.bodySm)
                        .frame(maxWidth: 460, alignment: .leading)
                } else {
                    ForEach(routines) { routine in
                        RoutineCard(routine: routine, palette: palette, context: context)
                    }
                }
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 30)
            .frame(maxWidth: 780, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct RoutineCard: View {
    @Bindable var routine: Routine
    let palette: ThemePalette
    let context: ModelContext

    var body: some View {
        ThemedCard(padding: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(routine.title)
                        .font(.system(size: TypeScale.body, weight: .semibold))
                        .foregroundStyle(palette.text)
                    Text(routine.activeWeekdays.sorted().map { Weekday.short($0) }.joined(separator: " · "))
                        .font(.system(size: TypeScale.caption))
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer()
                if routine.streak > 0 {
                    HStack(spacing: 6) {
                        StreakFlame(level: min(4, routine.streak), palette: palette, size: 18)
                        Text("\(routine.streak) day streak")
                            .font(.system(size: TypeScale.label, weight: .medium))
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                Button {
                    RoutineActions.archive(routine, in: context)
                } label: {
                    Image(systemName: "archivebox")
                        .font(.system(size: TypeScale.bodySm))
                        .foregroundStyle(palette.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Archive this routine")
            }
            HairlineDivider()
            VStack(alignment: .leading, spacing: 6) {
                ForEach(routine.activities) { activity in
                    HStack {
                        Text(activity.weekday.map { Weekday.full($0) } ?? "Every day")
                            .font(.system(size: TypeScale.caption, weight: .medium))
                            .foregroundStyle(palette.textTertiary)
                            .frame(width: 90, alignment: .leading)
                        Text(activity.title)
                            .font(.system(size: TypeScale.bodySm))
                            .foregroundStyle(palette.text)
                        Spacer()
                    }
                }
            }
        }
    }
}
