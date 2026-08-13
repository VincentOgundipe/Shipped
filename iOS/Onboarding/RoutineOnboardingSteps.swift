import SwiftUI

// MARK: - 0. Kind

struct KindStepView: View {
    @Environment(\.themePalette) private var palette
    var onChoose: (EntryKind) -> Void

    var body: some View {
        StepScaffold(
            step: .kind,
            headline: "What are we setting up?",
            subhead: "A goal counts down to a deadline. A routine just runs on repeat."
        ) {
            VStack(spacing: 10) {
                KindOptionCard(
                    title: "A new goal",
                    blurb: "Something with an end point — launch a store, hit a deadline.",
                    systemImage: "flag.checkered",
                    palette: palette
                ) { onChoose(.goal) }

                KindOptionCard(
                    title: "An existing routine",
                    blurb: "Something you already do on repeat — a workout split, a daily habit.",
                    systemImage: "repeat",
                    palette: palette
                ) { onChoose(.routine) }
            }
        } footer: {
            EmptyView()
        }
    }
}

private struct KindOptionCard: View {
    let title: String
    let blurb: String
    let systemImage: String
    let palette: ThemePalette
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: TypeScale.heading))
                    .foregroundStyle(palette.accent)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: TypeScale.subheading, weight: .semibold))
                        .foregroundStyle(palette.text)
                    Text(blurb)
                        .bodyStyle(palette, size: TypeScale.bodySm)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: TypeScale.bodySm))
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(16)
            .frame(minHeight: 64)
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: palette.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: palette.cornerRadius)
                    .stroke(palette.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Routine details

struct RoutineDetailsStepView: View {
    @Environment(\.themePalette) private var palette
    @Bindable var draft: OnboardingDraft
    let step: OnboardingStep
    var onNext: () -> Void

    private var canContinue: Bool {
        draft.routineTitle.trimmingCharacters(in: .whitespaces).count >= 3
            && !draft.routineWeekdays.isEmpty
            && draft.routineSource.count >= 10
    }

    var body: some View {
        StepScaffold(
            step: step,
            kind: .routine,
            headline: "Set up the routine",
            subhead: "Runs on repeat, no deadline — a workout split, a daily habit."
        ) {
            VStack(alignment: .leading, spacing: 18) {
                TextField("What's it called?", text: $draft.routineTitle)
                    .textFieldStyle(ShippedTextFieldStyle(palette: palette))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Which days").labelStyle(palette)
                    HStack(spacing: 6) {
                        ForEach(Weekday.displayOrder, id: \.self) { day in
                            let isOn = draft.routineWeekdays.contains(day)
                            Button {
                                if isOn { draft.routineWeekdays.remove(day) } else { draft.routineWeekdays.insert(day) }
                            } label: {
                                Text(Weekday.short(day))
                                    .font(.system(size: TypeScale.label, weight: .medium))
                                    .frame(width: 40, height: 36)
                                    .background(isOn ? palette.accent : palette.surface)
                                    .foregroundStyle(isOn ? palette.onAccent : palette.text)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(isOn ? .clear : palette.border, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                ThemedCard(padding: 12) {
                    HStack {
                        Text("Time per session")
                            .font(.system(size: TypeScale.body))
                            .foregroundStyle(palette.text)
                        Spacer()
                        Picker("", selection: $draft.capacity) {
                            ForEach(Capacity.allCases) { Text($0.label).tag($0) }
                        }
                        .labelsHidden()
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Do you already have a plan?").labelStyle(palette)
                    HStack(spacing: 10) {
                        ChoiceChip(title: "I have one", isSelected: draft.routineHasExistingPlan, palette: palette) {
                            draft.routineHasExistingPlan = true
                        }
                        ChoiceChip(title: "Build one for me", isSelected: !draft.routineHasExistingPlan, palette: palette) {
                            draft.routineHasExistingPlan = false
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(draft.routineHasExistingPlan ? "Paste it in" : "Describe what you want")
                        .labelStyle(palette)
                    TextEditor(text: $draft.routineSource)
                        .textEditorStyle(.plain)
                        .font(.system(size: TypeScale.bodySm))
                        .foregroundStyle(palette.text)
                        .scrollContentBackground(.hidden)
                        .frame(height: 130)
                        .padding(8)
                        .background(palette.surface)
                        .clipShape(RoundedRectangle(cornerRadius: palette.cornerRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: palette.cornerRadius)
                                .stroke(palette.border, lineWidth: 1)
                        )
                }
            }
        } footer: {
            Button("Build it", action: onNext)
                .buttonStyle(FilledPillButtonStyle(palette: palette, isDisabled: !canContinue))
                .disabled(!canContinue)
        }
    }
}

private struct ChoiceChip: View {
    let title: String
    let isSelected: Bool
    let palette: ThemePalette
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: TypeScale.bodySm, weight: .medium))
                .foregroundStyle(isSelected ? palette.onAccent : palette.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(isSelected ? palette.accent : palette.surface)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(isSelected ? .clear : palette.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Routine generating

struct RoutineGeneratingStepView: View {
    @Environment(\.themePalette) private var palette
    let routineTitle: String
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

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Setting up the routine").labelStyle(palette)
                        .padding(.top, 24)

                    Text("Building the schedule")
                        .displayStyle(palette, size: TypeScale.heading)

                    Text(routineTitle)
                        .bodyStyle(palette)
                        .fixedSize(horizontal: false, vertical: true)

                    PlanSkeletonList(palette: palette, rows: 5)
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
                Text("Couldn't build the schedule")
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

// MARK: - Routine review

struct RoutineReviewStepView: View {
    @Environment(\.themePalette) private var palette
    @Bindable var draft: OnboardingDraft
    let step: OnboardingStep
    var onRegenerate: () -> Void
    var onContinue: () -> Void

    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(step.progressLabel(kind: .routine)).labelStyle(palette)
                    .padding(.top, 24)

                Text(draft.routineTitle)
                    .displayStyle(palette, size: TypeScale.headingSm)

                Text("Swipe to delete anything that doesn't belong.")
                    .bodyStyle(palette, size: TypeScale.bodySm)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            List {
                ForEach(Array(draft.routineActivities.enumerated()), id: \.offset) { index, activity in
                    HStack(alignment: .top, spacing: 12) {
                        Text(activity.weekday.map { Weekday.short($0) } ?? "Daily")
                            .font(.system(size: TypeScale.label, weight: .medium))
                            .foregroundStyle(palette.textTertiary)
                            .frame(width: 48, alignment: .leading)
                            .padding(.top, 2)
                        Text(activity.title)
                            .font(.system(size: TypeScale.bodySm))
                            .foregroundStyle(palette.text)
                    }
                    .listRowBackground(palette.background)
                    .listRowSeparatorTint(palette.border)
                    .staggeredEntrance(index: min(index, 10), visible: appeared)
                }
                .onDelete { offsets in
                    withAnimation { draft.routineActivities.remove(atOffsets: offsets) }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .contentMargins(.bottom, 12, for: .scrollContent)

            VStack(spacing: 10) {
                Button("Lock it in", action: onContinue)
                    .buttonStyle(FilledPillButtonStyle(palette: palette, isDisabled: draft.routineActivities.isEmpty))
                    .disabled(draft.routineActivities.isEmpty)
                Button("Regenerate", action: onRegenerate)
                    .buttonStyle(OutlinePillButtonStyle(palette: palette))
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .onAppear { appeared = true }
    }
}
