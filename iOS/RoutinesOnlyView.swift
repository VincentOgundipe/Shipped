import SwiftUI
import SwiftData
import WidgetKit

/// Shown when the user has routines but no active deadline goal — Today would otherwise force
/// them back through onboarding just to see the routines they already set up.
struct RoutinesOnlyView: View {
    let routines: [Routine]
    @Environment(\.modelContext) private var context
    @Environment(\.themePalette) private var palette
    @State private var showOnboarding = false

    private var routinesToday: [Routine] {
        routines.filter { $0.isActive(on: .now) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today").displayStyle(palette, size: TypeScale.heading)
                    Text("No deadline goal running — just your routines.")
                        .bodyStyle(palette, size: TypeScale.bodySm)
                }

                if routinesToday.isEmpty {
                    Text("Nothing scheduled today.")
                        .bodyStyle(palette, size: TypeScale.bodySm)
                } else {
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

                Button("Start a goal too") { showOnboarding = true }
                    .buttonStyle(OutlinePillButtonStyle(palette: palette))
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingFlowView()
        }
    }
}
