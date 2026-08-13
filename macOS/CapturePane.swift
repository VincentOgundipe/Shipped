import SwiftUI
import SwiftData
import AppKit

/// Paste in a brain dump, notes, or a Notion page, then choose what it becomes: work folded
/// into the current plan, or a new goal you sign off on.
///
/// Deliberately a paste box rather than an automated Notes reader — you decide exactly what
/// leaves the device.
///
/// Note the layout: the editor is NOT inside a `ScrollView`. Nesting `TextEditor` in a
/// `ScrollView` on macOS renders it but never gives it focus, so pasting silently did nothing.
struct CapturePane: View {
    let goal: Goal?
    @Environment(\.modelContext) private var context
    @Environment(\.themePalette) private var palette

    @State private var text = ""
    @State private var state: CaptureState = .idle
    @State private var errorMessage: String?
    @State private var proposed: [TaskDraft] = []

    // Goal sign-off state — editable, because the user commits to this, not the model.
    @State private var questions: [String] = []
    @State private var answers: [String] = []
    @State private var draftTitle = ""
    @State private var draftDeadline = Date()
    @State private var draftCapacity: Capacity = .steady
    @State private var draftPlan: [TaskDraft] = []
    // Shown once capacity is picked, before deadline — capacity should inform the deadline,
    // not the other way around, so this surfaces a realistic estimate ahead of that field.
    @State private var timelineHint: ClaudeClient.TimelineEstimate?
    @State private var timelineHintTask: Task<Void, Never>?

    // Routine setup state.
    @State private var routineTitle = ""
    @State private var routineHasExistingPlan = true
    @State private var routineWeekdays: Set<Int> = [2, 3, 4, 5, 6]
    @State private var routineCapacity: Capacity = .steady
    @State private var routineSource = ""
    @State private var routineActivities: [ClaudeClient.RoutineActivityDraft] = []

    @FocusState private var editorFocused: Bool

    private enum CaptureState: Equatable {
        case idle
        case working(String)
        case clarifying
        case signOff
        case reviewingPlan
        case reviewingTasks
        case routineSetup
        case routineReview
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 34)
                .padding(.top, 30)
                .padding(.bottom, 16)

            switch state {
            case .idle:
                editor
                    .padding(.horizontal, 34)
                actions
                    .padding(.horizontal, 34)
                    .padding(.top, 14)
                    .padding(.bottom, 30)

            case .working(let label):
                VStack(alignment: .leading, spacing: 12) {
                    Text(label).bodyStyle(palette, size: TypeScale.bodySm)
                    PlanSkeletonList(palette: palette, rows: 5)
                }
                .padding(.horizontal, 34)
                Spacer()

            case .clarifying:
                clarifyingForm
            case .signOff:
                signOffForm
            case .reviewingPlan:
                planReview
            case .reviewingTasks:
                taskReview
            case .routineSetup:
                routineSetupForm
            case .routineReview:
                routineReview
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: TypeScale.bodySm))
                    .foregroundStyle(palette.accentSecondary)
                    .padding(.horizontal, 34)
                    .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Capture").labelStyle(palette)
            Text(headerTitle)
                .displayStyle(palette, size: TypeScale.heading)
            Text(headerBlurb)
                .bodyStyle(palette, size: TypeScale.bodySm)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 700, alignment: .leading)
    }

    private var headerTitle: String {
        switch state {
        case .clarifying: return "A few questions first"
        case .signOff: return "Sign off on this"
        case .reviewingPlan: return "Check the plan"
        case .reviewingTasks: return "Check these tasks"
        case .routineSetup: return "Set up the routine"
        case .routineReview: return "Check the schedule"
        default: return "Paste it in"
        }
    }

    private var headerBlurb: String {
        switch state {
        case .clarifying:
            return "Your notes were too vague to commit to a goal. Answer these and I'll try again."
        case .signOff:
            return "Nothing is created until you approve the goal and the deadline."
        case .reviewingPlan:
            return "Delete anything that doesn't belong before this becomes your plan."
        case .reviewingTasks:
            return "These get added to your existing plan."
        case .routineSetup:
            return "A routine runs on repeat with no deadline — a workout split, a daily habit."
        case .routineReview:
            return "Delete anything that doesn't belong before this becomes your schedule."
        default:
            return "Notes, a brain dump, a Notion page — anything. Nothing is read from your apps automatically; only what you paste here is sent."
        }
    }

    // MARK: - Editor

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $text)
                // `.plain` strips NSTextView's own built-in content inset — without it, real
                // typed text starts several points further in than a manually-padded
                // placeholder overlay does, so the two visibly don't line up.
                .textEditorStyle(.plain)
                .font(.system(size: TypeScale.bodySm))
                .foregroundStyle(palette.text)
                .scrollContentBackground(.hidden)
                .focused($editorFocused)
                .padding(10)
                .background(palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: palette.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: palette.cornerRadius)
                        .stroke(editorFocused ? palette.accent : palette.border, lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Paste or type here…")
                            .font(.system(size: TypeScale.bodySm))
                            .foregroundStyle(palette.textTertiary)
                            .padding(10)
                            .allowsHitTesting(false)
                    }
                }

            HStack(spacing: 8) {
                Text(text.isEmpty
                     ? "Empty"
                     : "\(text.split(whereSeparator: \.isWhitespace).count) words")
                    .font(.system(size: TypeScale.caption))
                    .foregroundStyle(palette.textTertiary)
                Spacer()
                if !text.isEmpty && text.count < 20 {
                    Text("Need a bit more to work with")
                        .font(.system(size: TypeScale.caption))
                        .foregroundStyle(palette.accentSecondary)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .onAppear { editorFocused = true }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            // Explicit paste, so it works even if the editor never took focus.
            Button {
                if let clip = NSPasteboard.general.string(forType: .string) {
                    text = text.isEmpty ? clip : text + "\n\n" + clip
                }
            } label: {
                Label("Paste", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(OutlinePillButtonStyle(palette: palette))

            if !text.isEmpty {
                Button("Clear") { text = "" }
                    .buttonStyle(OutlinePillButtonStyle(palette: palette))
            }

            Spacer()

            Button("Add to my plan") { Task { await addToPlan() } }
                .buttonStyle(FilledPillButtonStyle(
                    palette: palette,
                    isDisabled: text.count < 20 || goal == nil
                ))
                .disabled(text.count < 20 || goal == nil)
                .frame(width: 160)

            Button("New goal") { Task { await proposeGoal() } }
                .buttonStyle(FilledPillButtonStyle(palette: palette, isDisabled: text.count < 20))
                .disabled(text.count < 20)
                .frame(width: 130)

            Button("New routine") {
                routineSource = text
                routineHasExistingPlan = text.count >= 20
                state = .routineSetup
            }
            .buttonStyle(OutlinePillButtonStyle(palette: palette))
        }
    }

    // MARK: - Clarifying questions

    private var clarifyingForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                    VStack(alignment: .leading, spacing: 7) {
                        Text(question)
                            .font(.system(size: TypeScale.body, weight: .medium))
                            .foregroundStyle(palette.text)
                            .fixedSize(horizontal: false, vertical: true)
                        TextField("", text: Binding(
                            get: { index < answers.count ? answers[index] : "" },
                            set: { if index < answers.count { answers[index] = $0 } }
                        ), axis: .vertical)
                            .textFieldStyle(ShippedTextFieldStyle(palette: palette))
                    }
                }

                HStack(spacing: 10) {
                    Button("Continue") { Task { await proposeGoal(withAnswers: true) } }
                        .buttonStyle(FilledPillButtonStyle(
                            palette: palette,
                            isDisabled: allAnswersEmpty
                        ))
                        .disabled(allAnswersEmpty)
                    Button("Back") { state = .idle }
                        .buttonStyle(OutlinePillButtonStyle(palette: palette))
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 34)
            .padding(.bottom, 30)
            .frame(maxWidth: 700, alignment: .leading)
        }
    }

    private var allAnswersEmpty: Bool {
        answers.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    // MARK: - Sign-off

    private var signOffForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Goal").labelStyle(palette)
                    TextField("", text: $draftTitle, axis: .vertical)
                        .textFieldStyle(ShippedTextFieldStyle(palette: palette))
                }

                ThemedCard {
                    HStack {
                        Text("Pace")
                            .font(.system(size: TypeScale.body))
                            .foregroundStyle(palette.text)
                        Spacer()
                        Picker("", selection: $draftCapacity) {
                            ForEach(Capacity.allCases) { Text($0.label).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 170)
                    }
                    HairlineDivider()
                    HStack {
                        Text("Deadline")
                            .font(.system(size: TypeScale.body))
                            .foregroundStyle(palette.text)
                        Spacer()
                        DatePicker(
                            "",
                            selection: $draftDeadline,
                            in: (Calendar.appDefault.date(byAdding: .day, value: 3, to: .now) ?? .now)...,
                            displayedComponents: .date
                        )
                        .labelsHidden()
                    }
                }

                // Capacity determines what's realistic, so it's surfaced before the user
                // commits to a deadline rather than only reconciled silently by however hard
                // the plan generator has to squeeze the days that result.
                if let timelineHint {
                    Text("At this pace: ~\(timelineHint.days) days. \(timelineHint.rationale)")
                        .font(.system(size: TypeScale.caption))
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    if let timelineHint {
                        draftDeadline = Calendar.appDefault.date(
                            byAdding: .day,
                            value: max(3, timelineHint.days),
                            to: .now
                        ) ?? draftDeadline
                    }
                } label: {
                    Label("Not sure yet — use this estimate", systemImage: "sparkles")
                        .font(.system(size: TypeScale.bodySm, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.accent)
                .disabled(timelineHint == nil)

                Text(goal == nil
                     ? "\(dayCount) days from today."
                     : "\(dayCount) days from today. This runs alongside “\(goal!.title)”, not instead of it.")
                    .bodyStyle(palette, size: TypeScale.bodySm)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Button("Build the plan") { Task { await buildPlan() } }
                        .buttonStyle(FilledPillButtonStyle(palette: palette, isDisabled: titleTooShort))
                        .disabled(titleTooShort)
                    Button("Cancel") { reset() }
                        .buttonStyle(OutlinePillButtonStyle(palette: palette))
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 34)
            .padding(.bottom, 30)
            .frame(maxWidth: 700, alignment: .leading)
        }
        .onAppear { refreshTimelineHint() }
        .onChange(of: draftCapacity) { _, _ in refreshTimelineHint() }
    }

    private func refreshTimelineHint() {
        timelineHint = nil
        timelineHintTask?.cancel()
        timelineHintTask = Task {
            let estimate = try? await ClaudeClient.estimateGoalTimeline(
                goalTitle: draftTitle,
                capacity: draftCapacity
            )
            guard !Task.isCancelled else { return }
            timelineHint = estimate
        }
    }

    private var titleTooShort: Bool {
        draftTitle.trimmingCharacters(in: .whitespaces).count < 3
    }

    private var dayCount: Int {
        let cal = Calendar.appDefault
        return max(1, cal.dateComponents(
            [.day],
            from: cal.startOfDay(for: .now),
            to: cal.startOfDay(for: draftDeadline)
        ).day ?? 1)
    }

    // MARK: - Plan review (new goal)

    private var planReview: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(draftPlan.enumerated()), id: \.element.id) { index, draft in
                        DraftRow(draft: draft, palette: palette) {
                            draftPlan.removeAll { $0.id == draft.id }
                        }
                        if index < draftPlan.count - 1 { HairlineDivider() }
                    }
                }
                .padding(.horizontal, 34)
                .frame(maxWidth: 700, alignment: .leading)
            }

            HStack(spacing: 10) {
                Button("Create goal · \(draftPlan.count) days") { commitGoal() }
                    .buttonStyle(FilledPillButtonStyle(palette: palette, isDisabled: draftPlan.isEmpty))
                    .disabled(draftPlan.isEmpty)
                Button("Back") { state = .signOff }
                    .buttonStyle(OutlinePillButtonStyle(palette: palette))
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 18)
        }
    }

    // MARK: - Task review (existing goal)

    private var taskReview: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(proposed.enumerated()), id: \.element.id) { index, draft in
                        DraftRow(draft: draft, palette: palette) {
                            proposed.removeAll { $0.id == draft.id }
                        }
                        if index < proposed.count - 1 { HairlineDivider() }
                    }
                }
                .padding(.horizontal, 34)
                .frame(maxWidth: 700, alignment: .leading)
            }

            HStack(spacing: 10) {
                Button("Add \(proposed.count) to plan") { commitTasks() }
                    .buttonStyle(FilledPillButtonStyle(palette: palette, isDisabled: proposed.isEmpty))
                    .disabled(proposed.isEmpty)
                Button("Discard") { reset() }
                    .buttonStyle(OutlinePillButtonStyle(palette: palette))
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 18)
        }
    }

    // MARK: - Routine setup

    private var routineSetupForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Routine").labelStyle(palette)
                    TextField("What's it called?", text: $routineTitle, axis: .vertical)
                        .textFieldStyle(ShippedTextFieldStyle(palette: palette))
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("Which days").labelStyle(palette)
                    HStack(spacing: 6) {
                        ForEach(Weekday.displayOrder, id: \.self) { day in
                            let isOn = routineWeekdays.contains(day)
                            Button {
                                if isOn { routineWeekdays.remove(day) } else { routineWeekdays.insert(day) }
                            } label: {
                                Text(Weekday.short(day))
                                    .font(.system(size: TypeScale.label, weight: .medium))
                                    .frame(width: 42, height: 34)
                                    .background(isOn ? palette.accent : palette.surfaceRaised)
                                    .foregroundStyle(isOn ? palette.background : palette.text)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(PressableStyle())
                        }
                    }
                }

                ThemedCard {
                    HStack {
                        Text("Time per session")
                            .font(.system(size: TypeScale.body))
                            .foregroundStyle(palette.text)
                        Spacer()
                        Picker("", selection: $routineCapacity) {
                            ForEach(Capacity.allCases) { Text($0.label).tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 170)
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("Do you already have a plan for this?").labelStyle(palette)
                    HStack(spacing: 10) {
                        if routineHasExistingPlan {
                            Button("I have one") { routineHasExistingPlan = true }
                                .buttonStyle(FilledPillButtonStyle(palette: palette, isDisabled: false))
                        } else {
                            Button("I have one") { routineHasExistingPlan = true }
                                .buttonStyle(OutlinePillButtonStyle(palette: palette))
                        }
                        if !routineHasExistingPlan {
                            Button("Build one for me") { routineHasExistingPlan = false }
                                .buttonStyle(FilledPillButtonStyle(palette: palette, isDisabled: false))
                        } else {
                            Button("Build one for me") { routineHasExistingPlan = false }
                                .buttonStyle(OutlinePillButtonStyle(palette: palette))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text(routineHasExistingPlan ? "Paste it in" : "Describe what you want")
                        .labelStyle(palette)
                    TextEditor(text: $routineSource)
                        .textEditorStyle(.plain)
                        .font(.system(size: TypeScale.bodySm))
                        .foregroundStyle(palette.text)
                        .scrollContentBackground(.hidden)
                        .frame(height: 140)
                        .padding(8)
                        .background(palette.surface)
                        .clipShape(RoundedRectangle(cornerRadius: palette.cornerRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: palette.cornerRadius)
                                .stroke(palette.border, lineWidth: 1)
                        )
                }

                HStack(spacing: 10) {
                    Button("Build it") { Task { await buildRoutine() } }
                        .buttonStyle(FilledPillButtonStyle(
                            palette: palette,
                            isDisabled: routineTitle.trimmingCharacters(in: .whitespaces).count < 3
                                || routineWeekdays.isEmpty
                                || routineSource.count < 10
                        ))
                        .disabled(
                            routineTitle.trimmingCharacters(in: .whitespaces).count < 3
                                || routineWeekdays.isEmpty
                                || routineSource.count < 10
                        )
                    Button("Cancel") { reset() }
                        .buttonStyle(OutlinePillButtonStyle(palette: palette))
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 34)
            .padding(.bottom, 30)
            .frame(maxWidth: 700, alignment: .leading)
        }
    }

    // MARK: - Routine review

    private var routineReview: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(routineActivities.enumerated()), id: \.offset) { index, draft in
                        HStack(alignment: .top, spacing: 14) {
                            Text(draft.weekday.map { Weekday.short($0) } ?? "Daily")
                                .font(.system(size: TypeScale.label, weight: .medium))
                                .foregroundStyle(palette.textTertiary)
                                .frame(width: 56, alignment: .leading)
                            Text(draft.title)
                                .font(.system(size: TypeScale.bodySm))
                                .foregroundStyle(palette.text)
                            Spacer()
                            Button {
                                routineActivities.remove(at: index)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: TypeScale.caption))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(palette.textTertiary)
                        }
                        .padding(.vertical, 9)
                        if index < routineActivities.count - 1 { HairlineDivider() }
                    }
                }
                .padding(.horizontal, 34)
                .frame(maxWidth: 700, alignment: .leading)
            }

            HStack(spacing: 10) {
                Button("Create routine") { commitRoutine() }
                    .buttonStyle(FilledPillButtonStyle(palette: palette, isDisabled: routineActivities.isEmpty))
                    .disabled(routineActivities.isEmpty)
                Button("Back") { state = .routineSetup }
                    .buttonStyle(OutlinePillButtonStyle(palette: palette))
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 18)
        }
    }

    // MARK: - Actions

    private func addToPlan() async {
        guard let goal else { return }
        errorMessage = nil
        state = .working("Reading it and finding room in your plan…")
        do {
            proposed = try await ClaudeClient.scheduleCapturedWork(
                capturedText: text,
                goalTitle: goal.title,
                deadline: goal.deadline,
                capacity: goal.capacity,
                existingUpcoming: goal.upcomingUnfinishedTasks.map(\.title)
            )
            guard !proposed.isEmpty else {
                errorMessage = "Nothing actionable in there that isn't already scheduled."
                state = .idle
                return
            }
            state = .reviewingTasks
        } catch {
            errorMessage = error.localizedDescription
            state = .idle
        }
    }

    private func proposeGoal(withAnswers: Bool = false) async {
        errorMessage = nil
        state = .working(withAnswers ? "Working it out…" : "Reading your notes…")
        do {
            let pairs = withAnswers
                ? zip(questions, answers).map { (question: $0.0, answer: $0.1) }
                : []
            let suggestion = try await ClaudeClient.suggestGoal(from: text, answers: pairs)

            // Vague notes make vague goals, so the model may come back with questions.
            if suggestion.needsClarification, let asked = suggestion.questions, !withAnswers {
                questions = asked
                answers = Array(repeating: "", count: asked.count)
                state = .clarifying
                return
            }

            draftTitle = suggestion.title
            draftDeadline = Calendar.appDefault.date(
                byAdding: .day,
                value: max(3, suggestion.days),
                to: .now
            ) ?? .now
            state = .signOff
        } catch {
            errorMessage = error.localizedDescription
            state = withAnswers ? .clarifying : .idle
        }
    }

    private func buildPlan() async {
        errorMessage = nil
        state = .working("Reverse-engineering the plan…")
        do {
            draftPlan = try await ClaudeClient.generatePlan(
                goalTitle: draftTitle,
                deadline: draftDeadline,
                capacity: draftCapacity,
                sourceMaterial: text
            )
            guard !draftPlan.isEmpty else {
                errorMessage = "The plan came back empty. Try again."
                state = .signOff
                return
            }
            state = .reviewingPlan
        } catch {
            errorMessage = error.localizedDescription
            state = .signOff
        }
    }

    private func buildRoutine() async {
        errorMessage = nil
        state = .working(routineHasExistingPlan ? "Reading your plan…" : "Building the schedule…")
        do {
            routineActivities = try await ClaudeClient.generateRoutineActivities(
                title: routineTitle,
                activeWeekdays: Array(routineWeekdays),
                capacity: routineCapacity,
                sourceMaterial: routineSource,
                isExistingPlan: routineHasExistingPlan
            )
            guard !routineActivities.isEmpty else {
                errorMessage = "That came back empty. Try again."
                state = .routineSetup
                return
            }
            state = .routineReview
        } catch {
            errorMessage = error.localizedDescription
            state = .routineSetup
        }
    }

    private func commitRoutine() {
        context.insert(CapturedDocument(
            text: routineSource,
            source: CaptureSource.paste,
            outcome: "routine",
            relatedGoalTitle: routineTitle
        ))
        let routine = Routine(
            title: routineTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            activeWeekdays: Array(routineWeekdays),
            activities: routineActivities.map {
                RoutineActivityItem(title: $0.title, weekday: $0.weekday)
            }
        )
        context.insert(routine)
        try? context.save()
        reset()
    }

    private func commitGoal() {
        // Keep the source material so later features can reach back over it.
        context.insert(CapturedDocument(
            text: text,
            source: CaptureSource.paste,
            outcome: "goal",
            relatedGoalTitle: draftTitle
        ))

        let newGoal = Goal(
            title: draftTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            deadline: draftDeadline,
            capacity: draftCapacity
        )
        // Runs alongside whatever's already active rather than replacing it — multiple goals
        // can run in parallel now, so a new one from Capture shouldn't silently archive the
        // others.
        newGoal.priorityRank = GoalActions.nextPriorityRank(in: context)
        context.insert(newGoal)
        for (index, draft) in draftPlan.enumerated() {
            guard let date = draft.parsedDate else { continue }
            context.insert(DailyTask(date: date, title: draft.title, order: index, goal: newGoal))
        }
        try? context.save()
        reset()
    }

    private func commitTasks() {
        guard let goal else { return }
        context.insert(CapturedDocument(
            text: text,
            source: CaptureSource.paste,
            outcome: "tasks",
            relatedGoalTitle: goal.title
        ))
        let baseOrder = (goal.tasks.map(\.order).max() ?? 0) + 1
        for (index, draft) in proposed.enumerated() {
            guard let date = draft.parsedDate else { continue }
            context.insert(
                DailyTask(date: date, title: draft.title, order: baseOrder + index, goal: goal)
            )
        }
        try? context.save()
        reset()
    }

    private func reset() {
        text = ""
        proposed = []
        draftPlan = []
        questions = []
        answers = []
        draftTitle = ""
        timelineHint = nil
        timelineHintTask?.cancel()
        routineTitle = ""
        routineHasExistingPlan = true
        routineWeekdays = [2, 3, 4, 5, 6]
        routineCapacity = .steady
        routineSource = ""
        routineActivities = []
        state = .idle
    }
}

private struct DraftRow: View {
    let draft: TaskDraft
    let palette: ThemePalette
    var onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(draft.parsedDate?.formatted(.dateTime.month(.abbreviated).day()) ?? "—")
                .font(.system(size: TypeScale.label, weight: .medium))
                .foregroundStyle(palette.textTertiary)
                .frame(width: 56, alignment: .leading)
            Text(draft.title)
                .font(.system(size: TypeScale.bodySm))
                .foregroundStyle(palette.text)
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: TypeScale.caption))
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.textTertiary)
        }
        .padding(.vertical, 9)
    }
}
