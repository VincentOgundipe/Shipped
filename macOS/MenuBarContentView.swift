import SwiftUI
import SwiftData

struct MenuBarContentView: View {
    @Query(
        filter: #Predicate<Goal> { !$0.isArchived },
        sort: \Goal.priorityRank
    ) private var goals: [Goal]
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var status: CheckInStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let goal = goals.first {
                Text(goal.title)
                    .font(.headline)
                Text("Deadline \(goal.deadline.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                let todaysTasks = goal.tasks
                    .filter { Calendar.appDefault.isDateInToday($0.date) }
                    .sorted { $0.order < $1.order }

                if todaysTasks.isEmpty {
                    Text("Nothing scheduled today.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(todaysTasks) { task in
                        Button {
                            task.isDone.toggle()
                            task.markDirty()
                            try? context.save()
                            status.refresh()
                        } label: {
                            HStack {
                                Image(systemName: task.isDone ? "checkmark.square.fill" : "square")
                                Text(task.title)
                                    .strikethrough(task.isDone)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

            } else {
                Text("No goal set yet.")
                    .font(.headline)
                Text("Start one from Capture, or on your iPhone — it syncs here automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Toggle("Launch at login", isOn: Binding(
                get: { LoginItem.isEnabled },
                set: { LoginItem.setEnabled($0) }
            ))
            .font(.caption)

            Divider()
            Button("Quit Shipped") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(14)
        .frame(width: 300)
        .onAppear { status.refresh() }
    }
}
