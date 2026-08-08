import SwiftUI

@main
struct FitnessTrackerApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(model)
                .tint(Theme.accent)
                .task { await model.bootstrap() }
        }
    }
}

struct RootTabView: View {
    enum Tab: String {
        case history, workout, exercises, profile
    }

    @State private var selection: Tab = {
        #if DEBUG
        // Screenshot/dev hook: SIMCTL_CHILD_UITAB=exercises simctl launch …
        if let raw = ProcessInfo.processInfo.environment["UITAB"],
           let tab = Tab(rawValue: raw) {
            return tab
        }
        #endif
        return .history
    }()

    var body: some View {
        TabView(selection: $selection) {
            HistoryView()
                .tabItem { Label("History", systemImage: "clock") }
                .tag(Tab.history)
            PlaceholderView(title: "Workout",
                            message: "Templates and live logging arrive in the next phase.")
                .tabItem { Label("Workout", systemImage: "dumbbell") }
                .tag(Tab.workout)
            ExercisesView()
                .tabItem { Label("Exercises", systemImage: "list.bullet") }
                .tag(Tab.exercises)
            PlaceholderView(title: "Profile",
                            message: "Streaks, weekly goal, and body weight arrive in a later phase.")
                .tabItem { Label("Profile", systemImage: "person") }
                .tag(Tab.profile)
        }
    }
}

struct PlaceholderView: View {
    let title: String
    let message: String

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                Text(title).font(.title2.weight(.bold)).foregroundStyle(Theme.ink)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .appBackground()
        }
    }
}
