import SwiftUI

@main
struct FitnessTrackerApp: App {
    @State private var model = AppModel()
    @State private var session = WorkoutSessionModel()
    @State private var sync = SyncModel()
    @State private var importResult: String?
    // A CSV opened at cold launch arrives before bootstrap has a database;
    // the URL is only delivered once, so it must be held until then.
    @State private var pendingImportURL: URL?
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(model)
                .environment(session)
                .environment(sync)
                .tint(Theme.accent)
                // A CSV shared from Strong's export sheet lands here.
                .onOpenURL { url in
                    if model.db != nil {
                        Task { importResult = await model.importStrongCSV(from: url) }
                    } else {
                        pendingImportURL = url
                    }
                }
                .alert("Strong Import", isPresented: .init(
                    get: { importResult != nil },
                    set: { if !$0 { importResult = nil } })) {
                    Button("OK") { importResult = nil }
                } message: {
                    Text(importResult ?? "")
                }
                .task {
                    await model.bootstrap()
                    if let db = model.db {
                        session.configure(db: db)
                        session.resumeIfNeeded(baselines: model.bestE1RMByExerciseId,
                                               repBaselines: model.bestRepsByExerciseId,
                                               exerciseNames: model.exerciseNames)
                        await sync.configure(db: db)
                        sync.pushSoon()
                    }
                    if let url = pendingImportURL {
                        pendingImportURL = nil
                        importResult = await model.importStrongCSV(from: url)
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        // Debounced set edits must hit disk before a kill.
                        session.flushPendingSaves()
                    }
                    if phase == .active || phase == .background {
                        sync.pushSoon()
                    }
                }
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
            WorkoutTabView()
                .tabItem { Label("Workout", systemImage: "dumbbell") }
                .tag(Tab.workout)
            ExercisesView()
                .tabItem { Label("Exercises", systemImage: "list.bullet") }
                .tag(Tab.exercises)
            ProfileView()
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
