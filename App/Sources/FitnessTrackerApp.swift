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
    var body: some View {
        TabView {
            HistoryView()
                .tabItem { Label("History", systemImage: "clock") }
            PlaceholderView(title: "Workout",
                            message: "Templates and live logging arrive in the next phase.")
                .tabItem { Label("Workout", systemImage: "dumbbell") }
            ExercisesView()
                .tabItem { Label("Exercises", systemImage: "list.bullet") }
            PlaceholderView(title: "Profile",
                            message: "Streaks, weekly goal, and body weight arrive in a later phase.")
                .tabItem { Label("Profile", systemImage: "person") }
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
