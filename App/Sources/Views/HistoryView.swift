import FitnessKit
import SwiftUI

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(WorkoutSessionModel.self) private var session
    @State private var path = NavigationPath()
    /// Workout awaiting "discard the running session?" confirmation.
    @State private var pendingRepeat: LoadedWorkout?

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch model.state {
                case .loading:
                    ProgressView("Importing history…")
                case .failed(let message):
                    Text(message).foregroundStyle(Theme.inkSecondary).padding()
                case .ready where model.monthSections.isEmpty:
                    VStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.title)
                            .foregroundStyle(Theme.inkTertiary)
                        Text("No workouts yet")
                            .font(.headline)
                            .foregroundStyle(Theme.ink)
                        Text("Start a workout from the Workout tab, or import your Strong history from Profile.")
                            .font(.footnote)
                            .foregroundStyle(Theme.inkSecondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 280)
                    }
                case .ready:
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(model.monthSections) { section in
                                MonthHeader(section: section)
                                ForEach(section.workouts) { workout in
                                    // Tap gesture (not NavigationLink) so the
                                    // repeat button inside the card wins taps.
                                    WorkoutCard(workout: workout,
                                                prCount: model.prCounts[workout.id] ?? 0) {
                                        repeatTapped(workout)
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture { path.append(workout.id) }
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationDestination(for: String.self) { workoutId in
                if let workout = model.workoutsById[workoutId] {
                    WorkoutDetailView(workout: workout)
                } else {
                    Text("This workout is no longer available.")
                        .foregroundStyle(Theme.inkSecondary)
                        .appBackground()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .appBackground()
            .navigationTitle("History")
            .alert("A workout is already in progress.", isPresented: .init(
                get: { pendingRepeat != nil },
                set: { if !$0 { pendingRepeat = nil } })) {
                Button("Discard It & Start", role: .destructive) {
                    if let workout = pendingRepeat { startRepeat(workout) }
                    pendingRepeat = nil
                }
                Button("Cancel", role: .cancel) { pendingRepeat = nil }
            } message: {
                Text("Repeating \(pendingRepeat?.name ?? "this workout") discards the workout you have running now.")
            }
            #if DEBUG
            // Screenshot/dev hook: SIMCTL_CHILD_OPEN_WORKOUT=latest. Waits for
            // load + a settle beat; pushing during launch storms NavigationStack.
            .task {
                guard ProcessInfo.processInfo.environment["OPEN_WORKOUT"] == "latest" else { return }
                while !model.isReady {
                    do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                }
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                if let id = model.monthSections.first?.workouts.first?.id {
                    path.append(id)
                }
            }
            #endif
        }
    }

    private func repeatTapped(_ workout: LoadedWorkout) {
        if session.isActive {
            pendingRepeat = workout
        } else {
            startRepeat(workout)
        }
    }

    /// Starts a new session mirroring the workout — same exercises and rest
    /// times, sets prefilled with its lifts.
    private func startRepeat(_ workout: LoadedWorkout) {
        guard model.isReady else { return }
        session.startRepeating(workout, name: WorkoutNames.random(),
                               baselines: model.bestE1RMByExerciseId,
                               repBaselines: model.bestRepsByExerciseId,
                               exerciseNames: model.exerciseNames)
        session.isPresented = true
    }
}

private struct MonthHeader: View {
    let section: AppModel.MonthSection

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(section.title).font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSecondary)
            Spacer()
            Text("\(section.workoutCount) workouts")
                .font(.caption)
                .foregroundStyle(Theme.inkTertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 6)
        .padding(.top, 8)
    }
}

private struct WorkoutCard: View {
    let workout: LoadedWorkout
    let prCount: Int
    let onRepeat: () -> Void

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d · h:mm a"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(workout.name)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                if prCount > 0 {
                    PRChip(count: prCount)
                }
                Button(action: onRepeat) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 30, height: 30)
                        .background(Theme.accent.opacity(0.09), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Repeat \(workout.name)")
            }
            Text(Self.dateFormatter.string(from: workout.startedAt))
                .font(.footnote)
                .foregroundStyle(Theme.inkTertiary)
                .padding(.top, 2)

            HStack(spacing: 14) {
                if let duration = workout.durationSeconds {
                    StatText(value: Format.duration(duration), label: "duration")
                }
                StatText(value: Format.volume(workout.volume), label: Format.unitLabel)
            }
            .padding(.top, 10)

            Divider().overlay(Theme.hairline).padding(.vertical, 9)

            VStack(alignment: .leading, spacing: 5) {
                ForEach(workout.exercises.prefix(3)) { exercise in
                    HStack {
                        Text(exercise.name)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Theme.ink.opacity(0.85))
                            .lineLimit(1)
                        Spacer()
                        if let best = bestSetText(exercise) {
                            Text(best)
                                .font(.footnote)
                                .foregroundStyle(Theme.inkTertiary)
                                .monospacedDigit()
                        }
                    }
                }
                if workout.exercises.count > 3 {
                    Text("+\(workout.exercises.count - 3) more")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func bestSetText(_ exercise: LoadedExercise) -> String? {
        let best = exercise.sets.max {
            ($0.e1RM ?? $0.weight ?? 0) < ($1.e1RM ?? $1.weight ?? 0)
        }
        return best.map { Format.set($0).replacingOccurrences(of: "×", with: " × ") }
    }
}

struct PRChip: View {
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .stroke(AngularGradient(colors: Theme.rainbow, center: .center), lineWidth: 3)
                .frame(width: 12, height: 12)
            Text(count == 1 ? "1 PR" : "\(count) PRs")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color(red: 178 / 255, green: 123 / 255, blue: 0))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color(red: 1, green: 247 / 255, blue: 232 / 255), in: Capsule())
    }
}

private struct StatText: View {
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Text(value).font(.footnote.weight(.semibold)).foregroundStyle(Theme.ink).monospacedDigit()
            Text(label).font(.footnote).foregroundStyle(Theme.inkSecondary)
        }
    }
}
