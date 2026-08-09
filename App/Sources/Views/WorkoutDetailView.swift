import FitnessKit
import SwiftUI

struct WorkoutDetailView: View {
    @Environment(AppModel.self) private var model
    let workout: LoadedWorkout

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d, yyyy · h:mm a"
        return f
    }()

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                Text(Self.dateFormatter.string(from: workout.startedAt))
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)

                HStack(spacing: 14) {
                    if let duration = workout.durationSeconds {
                        summaryTile(Format.duration(duration), "Duration")
                    }
                    summaryTile(Format.volume(workout.volume), "Volume (lbs)")
                    summaryTile("\(workout.exercises.reduce(0) { $0 + $1.sets.count })", "Sets")
                }

                ForEach(workout.exercises) { exercise in
                    ExerciseCard(exercise: exercise,
                                 bestE1RM: model.bestE1RMByExerciseId[exercise.exerciseId])
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 24)
        }
        .appBackground()
        .navigationTitle(workout.name)
        .navigationBarTitleDisplayMode(.large)
    }

    private func summaryTile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline).foregroundStyle(Theme.ink).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(Theme.inkSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

private struct ExerciseCard: View {
    let exercise: LoadedExercise
    let bestE1RM: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(exercise.name)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Theme.ink)

            ForEach(exercise.sets) { set in
                HStack {
                    Text(set.isWarmup ? "W" : "\(set.position)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(set.isWarmup ? Theme.ringMid : Theme.inkSecondary)
                        .frame(width: 22)
                        .monospacedDigit()
                    Text(Format.set(set).replacingOccurrences(of: "×", with: " × "))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.ink)
                        .monospacedDigit()
                    Spacer()
                    IntensityRing(ratio: ratio(for: set), size: 22)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func ratio(for set: LoadedSet) -> Double? {
        guard let e1RM = set.e1RM, let bestE1RM, bestE1RM > 0 else { return nil }
        return e1RM / bestE1RM
    }
}
