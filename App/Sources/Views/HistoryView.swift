import FitnessKit
import SwiftUI

struct HistoryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                switch model.state {
                case .loading:
                    ProgressView("Importing history…")
                case .failed(let message):
                    Text(message).foregroundStyle(Theme.inkSecondary).padding()
                case .ready:
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(model.monthSections) { section in
                                MonthHeader(section: section)
                                ForEach(section.workouts) { workout in
                                    NavigationLink(value: workout.id) {
                                        WorkoutCard(workout: workout,
                                                    prCount: model.prCounts[workout.id] ?? 0)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationDestination(for: String.self) { workoutId in
                if let workout = model.monthSections
                    .flatMap(\.workouts).first(where: { $0.id == workoutId }) {
                    WorkoutDetailView(workout: workout)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .appBackground()
            .navigationTitle("History")
        }
    }
}

private struct MonthHeader: View {
    let section: AppModel.MonthSection

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(section.title).font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSecondary)
            Spacer()
            Text("\(section.workoutCount) workouts · \(Format.duration(section.totalSeconds)) total")
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
            }
            Text(Self.dateFormatter.string(from: workout.startedAt))
                .font(.footnote)
                .foregroundStyle(Theme.inkTertiary)
                .padding(.top, 2)

            HStack(spacing: 14) {
                if let duration = workout.durationSeconds {
                    StatText(value: Format.duration(duration), label: "duration")
                }
                StatText(value: Format.volume(workout.volume), label: "lbs")
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
