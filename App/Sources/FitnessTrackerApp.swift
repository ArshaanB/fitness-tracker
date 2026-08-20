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

    @Environment(WorkoutSessionModel.self) private var session

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
        @Bindable var session = session
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
        // The one full-screen workout cover for the whole app; every "open the
        // workout" path just flips session.isPresented.
        .fullScreenCover(isPresented: $session.isPresented) {
            ActiveWorkoutView()
        }
        // Minimized live session: floating bar above the tab bar, on every tab.
        .overlay(alignment: .bottom) {
            if session.isActive && !session.isPresented {
                MiniWorkoutBar { session.isPresented = true }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 56)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: session.isPresented)
    }
}

/// Compact banner for a minimized workout: name, live clock, live rest
/// countdown, and the session ring. Tap anywhere to reopen.
struct MiniWorkoutBar: View {
    @Environment(WorkoutSessionModel.self) private var session
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                IntensityRing(ratio: session.sessionIntensity, size: 24,
                              isRecord: session.sessionIsRecord)
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.name)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let elapsed = max(Int(context.date.timeIntervalSince(session.startedAt)), 0)
                        Text("\(Format.duration(elapsed)) · \(session.completedSets) of \(session.totalSets) sets")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.75))
                            .monospacedDigit()
                    }
                }
                Spacer()
                if let rest = session.rest {
                    TimelineView(.periodic(from: .now, by: 0.5)) { context in
                        let remaining = max(0, Int(rest.endDate.timeIntervalSince(context.date).rounded()))
                        HStack(spacing: 4) {
                            Image(systemName: "timer")
                            Text(String(format: "%d:%02d", remaining / 60, remaining % 60))
                                .monospacedDigit()
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Theme.accent, in: Capsule())
                    }
                }
                Image(systemName: "chevron.up")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.ink, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Theme.ink.opacity(0.35), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Reopen workout \(session.name)")
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
