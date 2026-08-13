import SwiftUI
import SwiftData

/// Reorder priority across active goals, and jump into any one goal's settings — shown when
/// there's more than one goal running, where a single toolbar gear can't map to "the" goal.
struct GoalsListView: View {
    let goals: [Goal]
    @Environment(\.modelContext) private var context
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var orderedGoals: [Goal] = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(orderedGoals) { goal in
                    NavigationLink {
                        SettingsView(goal: goal)
                            .environment(\.themePalette, palette)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(goal.title)
                                .font(.system(size: TypeScale.body, weight: .medium))
                                .foregroundStyle(palette.text)
                            Text(goal.isComplete ? "Complete" : goal.runSummary)
                                .font(.system(size: TypeScale.caption))
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                    .listRowBackground(palette.background)
                }
                .onMove { indices, newOffset in
                    orderedGoals.move(fromOffsets: indices, toOffset: newOffset)
                    GoalActions.setPriorityOrder(orderedGoals, in: context)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(palette.background)
            .navigationTitle("Goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { orderedGoals = goals }
        }
    }
}
