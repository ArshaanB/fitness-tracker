import FitnessKit
import SwiftUI

struct WorkoutDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let workout: LoadedWorkout

    @State private var showDeleteConfirm = false

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
                    summaryTile(Format.volume(workout.volume), "Volume (\(Format.unitLabel))")
                    summaryTile("\(workout.exercises.reduce(0) { $0 + $1.sets.count })", "Sets")
                }

                ForEach(workout.exercises) { exercise in
                    ExerciseCard(exercise: exercise,
                                 bestE1RM: model.bestE1RMByExerciseId[exercise.exerciseId],
                                 bestReps: model.bestRepsByExerciseId[exercise.exerciseId])
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 24)
        }
        .appBackground()
        .navigationTitle(workout.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Delete Workout", systemImage: "trash")
                    }
                    .tint(.red)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Theme.inkSecondary)
                }
            }
        }
        .alert("Delete this workout?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                model.deleteWorkout(id: workout.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every set from \(workout.name) will be removed. Records and charts recompute without it.")
        }
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
    let bestReps: Int?

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
        if let weight = set.weight, weight > 0,
           let e1RM = set.e1RM, let bestE1RM, bestE1RM > 0 {
            return e1RM / bestE1RM
        }
        // Bodyweight sets — rep-only movements (Chin Up, Pull Up…) AND
        // 0-weight sets of weighted exercises: score reps vs the rep record.
        if (set.weight ?? 0) == 0, let reps = set.reps, let bestReps, bestReps > 0 {
            return Double(reps) / Double(bestReps)
        }
        return nil
    }
}
