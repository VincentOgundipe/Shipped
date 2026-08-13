import SwiftUI
import SwiftData
import WidgetKit

struct SettingsView: View {
    @Bindable var goal: Goal
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.themePalette) private var palette

    @AppStorage(AppSettings.themeModeKey, store: AppSettings.defaults)
    private var themeModeRaw = ThemeMode.light.rawValue
    @AppStorage(AppSettings.focusModeKey, store: AppSettings.defaults)
    private var focusMode = false

    @State private var transition = ThemeTransition()
    @State private var lastTap: CGPoint = .zero
    @State private var showDeleteConfirm = false
    @State private var exportURL: URL?
    @State private var isSyncing = false
    @State private var syncError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    appearanceSection
                    focusSection
                    checkInSection
                    goalSection
                    syncSection
                    dataSection
                    dangerSection
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 20)
            }
            .screenBackground()
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(palette.accent)
                }
            }
        }
        .themeReveal(transition)
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Appearance").labelStyle(palette)

            VStack(spacing: 8) {
                ForEach(ThemeMode.allCases) { mode in
                    let isSelected = (ThemeMode(storedValue: themeModeRaw) ?? .light) == mode
                    Button {
                        guard !isSelected else { return }
                        transition.run(to: mode, from: .point(lastTap)) {
                            themeModeRaw = mode.rawValue
                            WidgetCenter.shared.reloadAllTimelines()
                        }
                    } label: {
                        HStack(spacing: 14) {
                            ThemeSwatch(mode: mode)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.label)
                                    .font(.system(size: TypeScale.body, weight: .semibold))
                                    .foregroundStyle(palette.text)
                                Text(mode.blurb)
                                    .bodyStyle(palette, size: TypeScale.bodySm)
                            }
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(palette.accent)
                            }
                        }
                        .padding(14)
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
                    // Records where the tap landed so the reveal starts from the finger.
                    .simultaneousGesture(
                        SpatialTapGesture(coordinateSpace: .global)
                            .onEnded { lastTap = $0.location }
                    )
                }
            }
        }
    }

    // MARK: - Focus

    private var focusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Focus").labelStyle(palette)
            ThemedCard {
                Toggle(isOn: Binding(
                    get: { focusMode },
                    set: { newValue in
                        withAnimation(Motion.settle) { focusMode = newValue }
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Today only")
                            .font(.system(size: TypeScale.body, weight: .semibold))
                            .foregroundStyle(palette.text)
                        Text("Hides the upcoming list and the legend. You won't be able to tick ahead.")
                            .bodyStyle(palette, size: TypeScale.bodySm)
                    }
                }
                .tint(palette.accent)
            }
        }
    }

    private var checkInSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Daily check-in").labelStyle(palette)
            ThemedCard {
                HStack {
                    Text("Ask me at")
                        .font(.system(size: TypeScale.body))
                        .foregroundStyle(palette.text)
                    Spacer()
                    Picker("Hour", selection: Binding(
                        get: { goal.checkInHour },
                        set: { newValue in
                            goal.checkInHour = newValue
                            goal.markDirty()
                            try? context.save()
                            Task {
                                await NotificationScheduler.scheduleDailyCheckIn(
                                    at: newValue,
                                    goalTitle: goal.title
                                )
                            }
                        }
                    )) {
                        ForEach(6..<24, id: \.self) { hour in
                            Text(HourLabel.text(for: hour)).tag(hour)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(palette.accent)
                }
            }
        }
    }

    private var goalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Goal").labelStyle(palette)
            ThemedCard {
                Text(goal.title)
                    .font(.system(size: TypeScale.body, weight: .semibold))
                    .foregroundStyle(palette.text)

                HairlineDivider()

                LabeledRow(label: "Deadline",
                           value: goal.deadline.formatted(date: .abbreviated, time: .omitted),
                           palette: palette)
                LabeledRow(label: "Pace", value: goal.capacity.label, palette: palette)
                LabeledRow(label: "Days left", value: "\(goal.daysRemaining)", palette: palette)
                if goal.recutCount > 0 {
                    LabeledRow(label: "Plan recut", value: "\(goal.recutCount)×", palette: palette)
                }
            }
        }
    }

    // MARK: - Data

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your data").labelStyle(palette)
            ThemedCard {
                if GoalActions.canUndoRecut(goal) {
                    Button {
                        withAnimation(Motion.settle) {
                            GoalActions.undoRecut(goal, in: context)
                        }
                        WidgetCenter.shared.reloadAllTimelines()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.uturn.backward")
                                .font(.system(size: TypeScale.bodySm))
                            Text("Undo the last recut")
                                .font(.system(size: TypeScale.body, weight: .medium))
                            Spacer()
                        }
                        .foregroundStyle(palette.text)
                    }
                    .buttonStyle(.plain)

                    Text("Restores the plan and deadline as they were before the recut.")
                        .bodyStyle(palette, size: TypeScale.bodySm)

                    HairlineDivider().padding(.vertical, 2)
                }

                if let exportURL {
                    ShareLink(item: exportURL) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: TypeScale.bodySm))
                            Text("Export everything")
                                .font(.system(size: TypeScale.body, weight: .medium))
                            Spacer()
                        }
                        .foregroundStyle(palette.text)
                    }
                } else {
                    Button {
                        prepareExport()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: TypeScale.bodySm))
                            Text("Export everything")
                                .font(.system(size: TypeScale.body, weight: .medium))
                            Spacer()
                        }
                        .foregroundStyle(palette.text)
                    }
                    .buttonStyle(.plain)
                }

                Text("Plain JSON of every goal and task, including archived ones. Deleting is permanent, so this is the only backup there is.")
                    .bodyStyle(palette, size: TypeScale.bodySm)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Writes the export to a temporary file so ShareLink has something to hand off.
    private func prepareExport() {
        guard let data = GoalActions.exportJSON(from: context) else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(GoalActions.exportFilename)
        try? data.write(to: url, options: .atomic)
        exportURL = url
    }


    // MARK: - Sync

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sync").labelStyle(palette)
            ThemedCard {
                if !SyncCoordinator.isConfigured {
                    Text("Not set up. Add your Supabase URL, key, and pairing ID to Secrets.swift on this device.")
                        .bodyStyle(palette, size: TypeScale.bodySm)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("This device ↔ Supabase")
                                .font(.system(size: TypeScale.body, weight: .semibold))
                                .foregroundStyle(palette.text)
                            Text(lastSyncedLabel)
                                .bodyStyle(palette, size: TypeScale.bodySm)
                        }
                        Spacer()
                        if isSyncing {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Sync now") { Task { await runSync() } }
                                .buttonStyle(OutlinePillButtonStyle(palette: palette))
                        }
                    }

                    if let syncError {
                        HairlineDivider()
                        Text(syncError)
                            .font(.system(size: TypeScale.bodySm))
                            .foregroundStyle(palette.accentSecondary)
                    }
                }
            }
        }
    }

    private var lastSyncedLabel: String {
        guard let date = SyncCoordinator.lastSyncedAt else { return "Never synced" }
        return "Last synced \(date.formatted(.relative(presentation: .named)))"
    }

    private func runSync() async {
        isSyncing = true
        syncError = nil
        defer { isSyncing = false }
        do {
            try await SyncCoordinator.sync(in: context)
        } catch {
            syncError = error.localizedDescription
        }
    }

    // MARK: - Danger

    /// What deletion actually costs, in the user's own numbers.
    private var deletionCost: String {
        var parts: [String] = ["your \(goal.tasks.count)-day plan"]
        let done = goal.tasks.filter(\.isDone).count
        if done > 0 { parts.append("\(done) completed task\(done == 1 ? "" : "s")") }
        if goal.streak > 0 { parts.append("your \(goal.streak)-day streak") }
        if goal.daysBanked > 0 {
            parts.append("\(goal.daysBanked) banked day\(goal.daysBanked == 1 ? "" : "s")")
        }

        guard parts.count > 1 else { return parts[0] }
        return parts.dropLast().joined(separator: ", ") + ", and " + parts[parts.count - 1]
    }

    private var dangerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Delete").labelStyle(palette)

            // Same flat surface and hairline border as every other card. The consequence is
            // carried by the words and the confirmation, not by a saturated block — a red
            // slab would be the loudest thing in an otherwise muted app.
            ThemedCard {
                Text("Deleting erases \(deletionCost).")
                    .font(.system(size: TypeScale.bodySm))
                    .foregroundStyle(palette.text)
                    .fixedSize(horizontal: false, vertical: true)

                Text("There is no undo and no backup.")
                    .bodyStyle(palette, size: TypeScale.bodySm)

                HairlineDivider()
                    .padding(.vertical, 2)

                Button {
                    showDeleteConfirm = true
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "trash")
                            .font(.system(size: TypeScale.bodySm, weight: .medium))
                        Text("Delete this goal")
                            .font(.system(size: TypeScale.body, weight: .medium))
                    }
                    .foregroundStyle(palette.destructive)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(palette.surfaceRaised)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(palette.destructive.opacity(0.55), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            .alert("Delete this goal?", isPresented: $showDeleteConfirm) {
                Button("Delete everything", role: .destructive) { deleteGoal() }
                Button("Keep it", role: .cancel) {}
            } message: {
                Text("This erases \(deletionCost). It can't be undone.")
            }
        }
        .padding(.top, 6)
    }

    private func deleteGoal() {
        NotificationScheduler.cancelDailyCheckIn()
        Task { await SyncCoordinator.pushTombstone(for: goal) }
        context.delete(goal)
        try? context.save()
        WidgetCenter.shared.reloadAllTimelines()
        dismiss()
    }
}

private struct LabeledRow: View {
    let label: String
    let value: String
    let palette: ThemePalette

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: TypeScale.bodySm))
                .foregroundStyle(palette.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: TypeScale.bodySm, weight: .medium))
                .foregroundStyle(palette.text)
        }
    }
}

/// A miniature of each theme so the choice is visual, not a word.
private struct ThemeSwatch: View {
    let mode: ThemeMode

    var body: some View {
        let p = Theme.palette(for: mode)
        return RoundedRectangle(cornerRadius: Radius.small)
            .fill(p.background)
            .frame(width: 44, height: 44)
            .overlay(
                VStack(spacing: 3) {
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 1.5).fill(p.gridDone)
                        RoundedRectangle(cornerRadius: 1.5).fill(p.gridDone)
                        RoundedRectangle(cornerRadius: 1.5).fill(p.gridMissed)
                    }
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 1.5).fill(p.gridDone)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(p.gridToday.opacity(0.3))
                            .overlay(RoundedRectangle(cornerRadius: 1.5).stroke(p.gridToday, lineWidth: 1))
                        RoundedRectangle(cornerRadius: 1.5).fill(p.gridFuture)
                    }
                }
                .padding(7)
            )
            .overlay(RoundedRectangle(cornerRadius: Radius.small).stroke(p.border, lineWidth: 1))
    }
}
