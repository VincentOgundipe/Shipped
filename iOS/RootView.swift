import SwiftUI
import SwiftData

struct RootView: View {
    @Query(
        filter: #Predicate<Goal> { !$0.isArchived },
        sort: \Goal.priorityRank
    ) private var goals: [Goal]
    @Query(
        filter: #Predicate<Routine> { !$0.isArchived },
        sort: \Routine.createdAt,
        order: .reverse
    ) private var routines: [Routine]
    var auth: AuthState

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            if !auth.isSignedIn {
                SignInView(auth: auth)
            } else if !goals.isEmpty {
                NavigationStack {
                    TodayView(goals: goals, routines: routines)
                }
            } else if !routines.isEmpty {
                NavigationStack {
                    RoutinesOnlyView(routines: routines)
                }
            } else {
                OnboardingFlowView()
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.9), value: auth.isSignedIn)
        .animation(.spring(response: 0.5, dampingFraction: 0.9), value: goals.isEmpty)
        // Best-effort and silent: a manual "Sync now" in Settings is where failures surface.
        // Syncing here too is what actually connects the phone to the Mac without the user
        // having to remember to press anything.
        .task { await trySync() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await trySync() } }
        }
    }

    private func trySync() async {
        guard SyncCoordinator.isConfigured else { return }
        try? await SyncCoordinator.sync(in: context)
    }
}
