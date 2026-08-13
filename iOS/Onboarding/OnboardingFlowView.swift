import SwiftUI
import SwiftData

/// Everything the user builds up before anything is written to the store. A half-finished
/// goal must never appear in the widget, so nothing persists until Commit.
@Observable
final class OnboardingDraft {
    var kind: EntryKind = .goal

    // Goal path
    var title = ""
    var deadline = Calendar.appDefault.date(byAdding: .day, value: 45, to: .now) ?? .now
    var capacity: Capacity = .steady
    var checkInHour = 20
    var plan: [TaskDraft] = []
    /// Set once capacity is picked, before deadline — capacity should inform what deadline is
    /// realistic, not the other way around, so this is surfaced ahead of that step.
    var timelineHint: ClaudeClient.TimelineEstimate?

    // Routine path
    var routineTitle = ""
    var routineWeekdays: Set<Int> = [2, 3, 4, 5, 6]
    var routineHasExistingPlan = true
    var routineSource = ""
    var routineActivities: [ClaudeClient.RoutineActivityDraft] = []
}

enum EntryKind {
    case goal
    case routine
}

enum OnboardingStep: Int, CaseIterable {
    case kind
    // Goal path
    case goal
    case capacity
    case deadline
    case generating
    case plan
    case commit
    // Routine path
    case routineDetails
    case routineGenerating
    case routineReview
    // Shared final step
    case widget

    private static let routineOnlySteps: Set<OnboardingStep> = [.routineDetails, .routineGenerating, .routineReview]

    /// Steps the user is asked to *do* something on. `generating` isn't one — it's a wait —
    /// so it doesn't get its own tick, and the counts the user reads line up with the bar.
    /// Differs by path since a routine has fewer steps than a goal.
    func countedSteps(kind: EntryKind) -> [OnboardingStep] {
        if kind == .routine || Self.routineOnlySteps.contains(self) {
            return [.kind, .routineDetails, .routineReview, .widget]
        }
        return [.kind, .goal, .capacity, .deadline, .plan, .commit, .widget]
    }

    /// 1-based position among counted steps, or nil while generating.
    func countedPosition(kind: EntryKind) -> Int? {
        countedSteps(kind: kind).firstIndex(of: self).map { $0 + 1 }
    }

    /// "Step 2 of 6" — generated, never hardcoded, so it can't drift again.
    func progressLabel(kind: EntryKind) -> String {
        guard let position = countedPosition(kind: kind) else { return "Building" }
        return "Step \(position) of \(countedSteps(kind: kind).count)"
    }

    var canGoBack: Bool {
        switch self {
        case .kind, .generating, .routineGenerating: return false
        default: return true
        }
    }

    var previous: OnboardingStep? {
        switch self {
        case .goal: return .kind
        case .capacity: return .goal
        case .deadline: return .capacity
        case .plan: return .deadline
        case .commit: return .plan
        case .routineDetails: return .kind
        case .routineReview: return .routineDetails
        case .widget: return nil // set dynamically — shared by both paths, see below
        default: return nil
        }
    }
}

struct OnboardingFlowView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.themePalette) private var palette

    @State private var draft = OnboardingDraft()
    @State private var step: OnboardingStep = .kind
    @State private var errorMessage: String?
    @State private var timelineHintTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if step.canGoBack {
                    Button {
                        if let previous = previousStep { advance(to: previous) }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: TypeScale.body, weight: .semibold))
                            .foregroundStyle(palette.text)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .transition(.opacity)
                }
                StepProgressBar(step: step, kind: draft.kind, palette: palette)
            }
            .padding(.horizontal, step.canGoBack ? 12 : 24)
            .padding(.top, 4)

            Group {
                switch step {
                case .kind:
                    KindStepView { chosen in
                        draft.kind = chosen
                        advance(to: chosen == .goal ? .goal : .routineDetails)
                    }
                case .goal:
                    GoalStepView(draft: draft, step: step) { advance(to: .capacity) }
                case .capacity:
                    CapacityStepView(draft: draft, step: step) {
                        refreshTimelineHint()
                        advance(to: .deadline)
                    }
                case .deadline:
                    DeadlineStepView(draft: draft, step: step) {
                        advance(to: .generating)
                        Task { await generate() }
                    }
                case .generating:
                    GeneratingStepView(
                        goalTitle: draft.title,
                        errorMessage: errorMessage,
                        onRetry: {
                            errorMessage = nil
                            Task { await generate() }
                        },
                        onBack: { advance(to: .deadline) }
                    )
                case .plan:
                    PlanRevealStepView(
                        draft: draft,
                        step: step,
                        onRegenerate: {
                            advance(to: .generating)
                            Task { await generate() }
                        },
                        onContinue: { advance(to: .commit) }
                    )
                case .commit:
                    CommitStepView(draft: draft, step: step) { advance(to: .widget) }
                case .routineDetails:
                    RoutineDetailsStepView(draft: draft, step: step) {
                        advance(to: .routineGenerating)
                        Task { await generateRoutine() }
                    }
                case .routineGenerating:
                    RoutineGeneratingStepView(
                        routineTitle: draft.routineTitle,
                        errorMessage: errorMessage,
                        onRetry: {
                            errorMessage = nil
                            Task { await generateRoutine() }
                        },
                        onBack: { advance(to: .routineDetails) }
                    )
                case .routineReview:
                    RoutineReviewStepView(
                        draft: draft,
                        step: step,
                        onRegenerate: {
                            advance(to: .routineGenerating)
                            Task { await generateRoutine() }
                        },
                        onContinue: { advance(to: .widget) }
                    )
                case .widget:
                    WidgetStepView(step: step, kind: draft.kind) {
                        if draft.kind == .routine { commitRoutine() } else { commit() }
                    }
                }
            }
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
        }
        .screenBackground()
    }

    /// `.widget` is shared by both paths and its predecessor depends on which one the user
    /// is on, which the step enum alone can't see.
    private var previousStep: OnboardingStep? {
        if step == .widget {
            return draft.kind == .routine ? .routineReview : .commit
        }
        return step.previous
    }

    private func advance(to next: OnboardingStep) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            step = next
        }
    }

    private func refreshTimelineHint() {
        draft.timelineHint = nil
        timelineHintTask?.cancel()
        timelineHintTask = Task {
            let estimate = try? await ClaudeClient.estimateGoalTimeline(
                goalTitle: draft.title,
                capacity: draft.capacity
            )
            guard !Task.isCancelled else { return }
            draft.timelineHint = estimate
        }
    }

    private func generate() async {
        errorMessage = nil
        do {
            let drafts = try await ClaudeClient.generatePlan(
                goalTitle: draft.title,
                deadline: draft.deadline,
                capacity: draft.capacity
            )
            guard !drafts.isEmpty else {
                errorMessage = "Claude returned an empty plan. Try again."
                return
            }
            draft.plan = drafts
            advance(to: .plan)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The only place onboarding touches the database, for the goal path.
    private func commit() {
        let goal = Goal(
            title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            deadline: draft.deadline,
            capacity: draft.capacity,
            checkInHour: draft.checkInHour
        )
        goal.priorityRank = GoalActions.nextPriorityRank(in: context)
        context.insert(goal)

        for (index, item) in draft.plan.enumerated() {
            guard let date = item.parsedDate else { continue }
            context.insert(DailyTask(date: date, title: item.title, order: index, goal: goal))
        }
        try? context.save()

        Task {
            await NotificationScheduler.scheduleDailyCheckIn(
                at: goal.checkInHour,
                goalTitle: goal.title
            )
        }
    }

    private func generateRoutine() async {
        errorMessage = nil
        do {
            let activities = try await ClaudeClient.generateRoutineActivities(
                title: draft.routineTitle,
                activeWeekdays: Array(draft.routineWeekdays),
                capacity: draft.capacity,
                sourceMaterial: draft.routineSource,
                isExistingPlan: draft.routineHasExistingPlan
            )
            guard !activities.isEmpty else {
                errorMessage = "That came back empty. Try again."
                return
            }
            draft.routineActivities = activities
            advance(to: .routineReview)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The only place onboarding touches the database, for the routine path.
    private func commitRoutine() {
        let routine = Routine(
            title: draft.routineTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            activeWeekdays: Array(draft.routineWeekdays),
            activities: draft.routineActivities.map {
                RoutineActivityItem(title: $0.title, weekday: $0.weekday)
            }
        )
        context.insert(routine)
        try? context.save()
    }
}

// MARK: - Progress bar

/// One tick per counted step, so the bar and the "Step N of M" label always agree.
struct StepProgressBar: View {
    let step: OnboardingStep
    let kind: EntryKind
    let palette: ThemePalette

    var body: some View {
        let steps = step.countedSteps(kind: kind)
        let reached = step.countedPosition(kind: kind) ?? 0
        HStack(spacing: 4) {
            ForEach(Array(steps.enumerated()), id: \.element.rawValue) { index, _ in
                Capsule()
                    .fill(index < reached ? palette.accent : palette.border)
                    .frame(height: 3)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: reached)
    }
}

// MARK: - Shared step chrome

struct StepScaffold<Content: View, Footer: View>: View {
    @Environment(\.themePalette) private var palette
    let step: OnboardingStep
    var kind: EntryKind = .goal
    let headline: String
    var subhead: String?
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(step.progressLabel(kind: kind)).labelStyle(palette)
                        .padding(.top, 24)

                    Text(headline)
                        .displayStyle(palette, size: TypeScale.heading)
                        .fixedSize(horizontal: false, vertical: true)

                    if let subhead {
                        Text(subhead)
                            .bodyStyle(palette)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    content
                        .padding(.top, 2)

                    // Absorbs leftover height so short steps sit as a top-aligned block
                    // instead of stranding the input in the middle of an empty screen.
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 10) { footer }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 24)
        }
    }
}
