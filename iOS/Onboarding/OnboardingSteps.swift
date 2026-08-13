import SwiftUI

// MARK: - 1. Goal

struct GoalStepView: View {
    @Environment(\.themePalette) private var palette
    @Bindable var draft: OnboardingDraft
    let step: OnboardingStep
    var onNext: () -> Void

    @FocusState private var focused: Bool

    private var canContinue: Bool {
        draft.title.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
    }

    var body: some View {
        StepScaffold(
            step: step,
            headline: "What are you trying to hit?",
            subhead: "One goal. Be specific enough that you'd know if you hit it."
        ) {
            TextField("Launch my Shopify store", text: $draft.title, axis: .vertical)
                .textFieldStyle(ShippedTextFieldStyle(palette: palette))
                .focused($focused)
                .submitLabel(.done)
                // Goals are full of brand and product names — autocorrect mangles them
                // ("print-on-demand" becomes "print-in-demand"), and this text is what the
                // whole plan gets generated from.
                .autocorrectionDisabled()
                .textInputAutocapitalization(.sentences)
                .onAppear { focused = true }
        } footer: {
            Button("Next", action: onNext)
                .buttonStyle(FilledPillButtonStyle(palette: palette, isDisabled: !canContinue))
                .disabled(!canContinue)
        }
    }
}

// MARK: - 2. Deadline

struct DeadlineStepView: View {
    @Environment(\.themePalette) private var palette
    @Bindable var draft: OnboardingDraft
    let step: OnboardingStep
    var onNext: () -> Void

    @State private var suggesting = false
    @State private var suggestError: String?

    private var dayCount: Int {
        let cal = Calendar.appDefault
        return max(1, cal.dateComponents(
            [.day],
            from: cal.startOfDay(for: .now),
            to: cal.startOfDay(for: draft.deadline)
        ).day ?? 1)
    }

    var body: some View {
        StepScaffold(
            step: step,
            headline: "By when?",
            subhead: "Not sure? I can suggest one from your pace instead of you guessing."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Button {
                    Task { await suggestDeadline() }
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(palette.accent.opacity(0.15))
                            if suggesting {
                                ProgressView().tint(palette.accent)
                            } else {
                                Image(systemName: "sparkles")
                                    .font(.system(size: TypeScale.body, weight: .semibold))
                                    .foregroundStyle(palette.accent)
                            }
                        }
                        .frame(width: 36, height: 36)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Not sure yet?")
                                .font(.system(size: TypeScale.body, weight: .semibold))
                                .foregroundStyle(palette.text)
                            Text(
                                draft.timelineHint.map { "Use the suggested \($0.days)-day estimate" }
                                    ?? "Let me suggest one from your pace"
                            )
                            .font(.system(size: TypeScale.bodySm))
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: TypeScale.bodySm, weight: .semibold))
                            .foregroundStyle(palette.accent)
                    }
                    .padding(14)
                    .background(palette.accent.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: palette.cornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: palette.cornerRadius)
                            .stroke(palette.accent.opacity(0.4), lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
                .disabled(suggesting)

                if let hint = draft.timelineHint {
                    Text(hint.rationale)
                        .font(.system(size: TypeScale.label))
                        .foregroundStyle(palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }

                if let suggestError {
                    Text(suggestError)
                        .font(.system(size: TypeScale.caption))
                        .foregroundStyle(palette.accentSecondary)
                        .padding(.horizontal, 4)
                }

                HStack(spacing: 10) {
                    Rectangle().fill(palette.border).frame(height: 1)
                    Text("or pick a date").font(.system(size: TypeScale.caption)).foregroundStyle(palette.textTertiary)
                    Rectangle().fill(palette.border).frame(height: 1)
                }

                ThemedCard(padding: 12) {
                    DatePicker(
                        "Deadline",
                        selection: $draft.deadline,
                        in: (Calendar.appDefault.date(byAdding: .day, value: 3, to: .now) ?? .now)...,
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .tint(palette.accent)
                }

                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("\(dayCount)")
                        .font(.system(size: TypeScale.heading, weight: palette.displayWeight))
                        .foregroundStyle(palette.accent)
                    Text("days from today")
                        .bodyStyle(palette)
                }
                .contentTransition(.numericText())
                .animation(Motion.snappy, value: dayCount)
            }
        } footer: {
            Button("Next", action: onNext)
                .buttonStyle(FilledPillButtonStyle(palette: palette))
        }
    }

    private func suggestDeadline() async {
        suggesting = true
        suggestError = nil
        defer { suggesting = false }
        do {
            let estimate = try await ClaudeClient.estimateGoalTimeline(
                goalTitle: draft.title,
                capacity: draft.capacity
            )
            draft.timelineHint = estimate
            withAnimation(Motion.snappy) {
                draft.deadline = Calendar.appDefault.date(
                    byAdding: .day,
                    value: max(3, estimate.days),
                    to: .now
                ) ?? draft.deadline
            }
        } catch {
            suggestError = error.localizedDescription
        }
    }
}

// MARK: - 3. Capacity

struct CapacityStepView: View {
    @Environment(\.themePalette) private var palette
    @Bindable var draft: OnboardingDraft
    let step: OnboardingStep
    var onNext: () -> Void

    var body: some View {
        StepScaffold(
            step: step,
            headline: "How hard can you go?",
            subhead: "Be honest. An overcooked plan gets abandoned by day three."
        ) {
            VStack(spacing: 10) {
                ForEach(Capacity.allCases) { option in
                    let isSelected = draft.capacity == option
                    Button {
                        withAnimation(Motion.snappy) { draft.capacity = option }
                    } label: {
                        HStack(spacing: 14) {
                            Circle()
                                .strokeBorder(isSelected ? palette.accent : palette.border, lineWidth: 2)
                                .background(
                                    Circle()
                                        .fill(isSelected ? palette.accent : .clear)
                                        .padding(5)
                                )
                                .frame(width: 24, height: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.label)
                                    .font(.system(size: TypeScale.subheading, weight: .semibold))
                                    .foregroundStyle(palette.text)
                                Text(option.blurb)
                                    .bodyStyle(palette, size: TypeScale.bodySm)
                            }
                            Spacer()
                        }
                        .padding(16)
                        .frame(minHeight: 64)
                        .background(palette.surface)
                        .clipShape(RoundedRectangle(cornerRadius: palette.cornerRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: palette.cornerRadius)
                                .stroke(
                                    isSelected ? palette.accent : palette.border,
                                    lineWidth: isSelected ? 2 : 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        } footer: {
            Button("Build my plan", action: onNext)
                .buttonStyle(FilledPillButtonStyle(palette: palette))
        }
    }
}

// MARK: - 4. Generating

struct GeneratingStepView: View {
    @Environment(\.themePalette) private var palette
    let goalTitle: String
    let errorMessage: String?
    var onRetry: () -> Void
    var onBack: () -> Void

    var body: some View {
        if let errorMessage {
            errorState(errorMessage)
        } else {
            loadingState
        }
    }

    /// A skeleton of the plan being written, rather than an anonymous spinner.
    private var loadingState: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Building your plan").labelStyle(palette)
                        .padding(.top, 24)

                    Text("Reverse-engineering")
                        .displayStyle(palette, size: TypeScale.heading)

                    Text(goalTitle)
                        .bodyStyle(palette)
                        .fixedSize(horizontal: false, vertical: true)

                    PlanSkeletonList(palette: palette, rows: 8)
                        .padding(.top, 8)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .scrollDisabled(true)
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: TypeScale.heading, weight: .light))
                    .foregroundStyle(palette.accentSecondary)
                Text("Couldn't build the plan")
                    .displayStyle(palette, size: TypeScale.headingSm)
                Text(message)
                    .bodyStyle(palette, size: TypeScale.bodySm)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
            VStack(spacing: 10) {
                Button("Try again", action: onRetry)
                    .buttonStyle(FilledPillButtonStyle(palette: palette))
                Button("Change my answers", action: onBack)
                    .buttonStyle(OutlinePillButtonStyle(palette: palette))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 5. Plan reveal

struct PlanRevealStepView: View {
    @Environment(\.themePalette) private var palette
    @Bindable var draft: OnboardingDraft
    let step: OnboardingStep
    var onRegenerate: () -> Void
    var onContinue: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(step.progressLabel(kind: draft.kind)).labelStyle(palette)
                    .padding(.top, 24)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(draft.plan.count)")
                        .font(.system(size: TypeScale.display, weight: palette.displayWeight))
                        .foregroundStyle(palette.accent)
                    Text(draft.plan.count == 1 ? "day of work" : "days of work")
                        .displayStyle(palette, size: TypeScale.headingSm)
                }

                Text("Swipe to delete anything that doesn't belong.")
                    .bodyStyle(palette, size: TypeScale.bodySm)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            List {
                ForEach(Array(draft.plan.enumerated()), id: \.element.id) { index, item in
                    HStack(alignment: .top, spacing: 12) {
                        Text(shortDate(item))
                            .font(.system(size: TypeScale.label, weight: .medium))
                            .foregroundStyle(palette.textTertiary)
                            .frame(width: 48, alignment: .leading)
                            .padding(.top, 2)
                        Text(item.title)
                            .font(.system(size: TypeScale.bodySm))
                            .foregroundStyle(palette.text)
                    }
                    .listRowBackground(palette.background)
                    .listRowSeparatorTint(palette.border)
                    .staggeredEntrance(index: min(index, 10), visible: appeared)
                }
                .onDelete { offsets in
                    withAnimation { draft.plan.remove(atOffsets: offsets) }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.bottom, 12, for: .scrollContent)

            VStack(spacing: 10) {
                Button("Lock it in", action: onContinue)
                    .buttonStyle(FilledPillButtonStyle(palette: palette, isDisabled: draft.plan.isEmpty))
                    .disabled(draft.plan.isEmpty)
                Button("Regenerate", action: onRegenerate)
                    .buttonStyle(OutlinePillButtonStyle(palette: palette))
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .onAppear { appeared = true }
    }

    private func shortDate(_ item: TaskDraft) -> String {
        guard let date = item.parsedDate else { return "—" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

// MARK: - 6. Commit

struct CommitStepView: View {
    @Environment(\.themePalette) private var palette
    @Bindable var draft: OnboardingDraft
    let step: OnboardingStep
    var onNext: () -> Void

    @State private var requesting = false

    var body: some View {
        StepScaffold(
            step: step,
            headline: "When should I ask?",
            subhead: "Once a day this app asks what you did. Pick a time you'll actually be free."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                ThemedCard {
                    HStack {
                        Text("Check in at")
                            .font(.system(size: TypeScale.body))
                            .foregroundStyle(palette.text)
                        Spacer()
                        Picker("Hour", selection: $draft.checkInHour) {
                            ForEach(6..<24, id: \.self) { hour in
                                Text(HourLabel.text(for: hour)).tag(hour)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(palette.accent)
                    }
                }

                Text("“What did you do today?” — every day at \(HourLabel.text(for: draft.checkInHour)), until \(draft.deadline.formatted(date: .abbreviated, time: .omitted)).")
                    .bodyStyle(palette, size: TypeScale.bodySm)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } footer: {
            Button {
                requesting = true
                Task {
                    await NotificationScheduler.requestAuthorization()
                    requesting = false
                    onNext()
                }
            } label: {
                if requesting {
                    ProgressView().tint(palette.onAccent)
                } else {
                    Text("Hold me to it")
                }
            }
            .buttonStyle(FilledPillButtonStyle(palette: palette))
            .disabled(requesting)
        }
    }
}

// MARK: - 7. Widget

struct WidgetStepView: View {
    @Environment(\.themePalette) private var palette
    let step: OnboardingStep
    var kind: EntryKind = .goal
    var onDone: () -> Void

    var body: some View {
        StepScaffold(
            step: step,
            kind: kind,
            headline: "Put it where you'll see it",
            subhead: "The grid fills in as you ship. Missed days stay visible."
        ) {
            VStack(alignment: .leading, spacing: 16) {
                WidgetPreviewCard(palette: palette)

                VStack(alignment: .leading, spacing: 11) {
                    InstructionRow(number: 1, text: "Long-press your home or lock screen", palette: palette)
                    InstructionRow(number: 2, text: "Tap Edit, then Add Widget", palette: palette)
                    InstructionRow(number: 3, text: "Search Shipped and add the grid", palette: palette)
                }
            }
        } footer: {
            Button("Done — take me in", action: onDone)
                .buttonStyle(FilledPillButtonStyle(palette: palette))
        }
    }
}

private struct InstructionRow: View {
    let number: Int
    let text: String
    let palette: ThemePalette

    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.system(size: TypeScale.label, weight: .bold))
                .foregroundStyle(palette.onAccent)
                .frame(width: 22, height: 22)
                .background(Circle().fill(palette.accent))
            Text(text)
                .bodyStyle(palette, size: TypeScale.bodySm)
        }
    }
}

/// A static sample of the widget so the user knows what they're adding.
private struct WidgetPreviewCard: View {
    let palette: ThemePalette

    private var sampleCells: [DayCell] {
        (0..<42).map { index in
            let status: DayStatus
            switch index {
            case 0..<9 where index % 4 == 3: status = .missed
            case 0..<9: status = .done
            case 9: status = .todayPending
            default: status = .future
            }
            return DayCell(id: index, date: .now, status: status)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Launch my Shopify store")
                .font(.system(size: TypeScale.caption, weight: .semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(palette.textTertiary)
            ProgressGridView(cells: sampleCells, palette: palette, columns: 14, spacing: 3)
        }
        .padding(14)
        .frame(maxWidth: 230)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: palette.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: palette.cornerRadius)
                .stroke(palette.border, lineWidth: 1)
        )
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
