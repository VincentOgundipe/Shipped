import SwiftUI
import SwiftData

/// The whole plan, grouped by week — Today only shows a handful of days ahead, this is where
/// the full shape of the plan is visible at once.
struct PlanView: View {
    @Bindable var goal: Goal
    @Environment(\.modelContext) private var context
    @Environment(\.themePalette) private var palette

    private var weeks: [(weekStart: Date, tasks: [DailyTask])] {
        let cal = Calendar.appDefault
        let sorted = goal.tasks.sorted { $0.date < $1.date }
        let grouped = Dictionary(grouping: sorted) { task in
            cal.dateInterval(of: .weekOfYear, for: task.date)?.start ?? task.date
        }
        return grouped.keys.sorted().map { (weekStart: $0, tasks: grouped[$0] ?? []) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
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

                ForEach(weeks, id: \.weekStart) { week in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Week of \(week.weekStart.formatted(.dateTime.month(.abbreviated).day()))")
                            .font(.system(size: TypeScale.label, weight: .semibold))
                            .foregroundStyle(palette.textTertiary)
                        ThemedCard(padding: 8) {
                            ForEach(Array(week.tasks.enumerated()), id: \.element.id) { index, task in
                                Button {
                                    withAnimation(Motion.snappy) { task.isDone.toggle() }
                                    task.markDirty()
                                    try? context.save()
                                } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: TypeScale.bodySm))
                                            .foregroundStyle(task.isDone ? palette.accent : palette.textTertiary)
                                        Text(task.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                                            .font(.system(size: TypeScale.label, weight: .medium))
                                            .foregroundStyle(palette.textTertiary)
                                            .frame(width: 84, alignment: .leading)
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
                                if index < week.tasks.count - 1 { HairlineDivider() }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 20)
        }
        .screenBackground()
        .navigationTitle("Plan")
        .navigationBarTitleDisplayMode(.inline)
    }
}
