import FitnessKit
import SwiftUI

/// Opens a finished workout in the workout screen's editor mode. Owns its own
/// session model, so editing history never touches a live session.
struct WorkoutEditorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let workoutId: String

    private enum LoadState { case loading, ready, missing }

    @State private var editor = WorkoutSessionModel(isEditor: true)
    @State private var state: LoadState = .loading

    var body: some View {
        Group {
            switch state {
            case .ready:
                ActiveWorkoutView().environment(editor)
            case .missing:
                Text("This workout is no longer available.")
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .appBackground()
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .appBackground()
            }
        }
        .presentationDragIndicator(.visible)
        .onAppear {
            guard case .loading = state, let db = model.db else { return }
            editor.configure(db: db)
            let loaded = editor.loadForEditing(workoutId: workoutId,
                                               baselines: model.bestE1RMByExerciseId,
                                               repBaselines: model.bestRepsByExerciseId,
                                               exerciseNames: model.exerciseNames)
            state = loaded ? .ready : .missing
            #if DEBUG
            // Scripted end-to-end test: SIMCTL_CHILD_EDIT_TEST=1 exercises
            // every edit operation, then closes; the database is then
            // inspected from outside.
            if loaded, ProcessInfo.processInfo.environment["EDIT_TEST"] != nil {
                Task { await runEditTest() }
            }
            #endif
        }
    }

    #if DEBUG
    private func runEditTest() async {
        do { try await Task.sleep(for: .seconds(2)) } catch { return }
        editor.rename("Edited \(Int(Date().timeIntervalSince1970) % 100_000)")
        editor.setTiming(startedAt: editor.startedAt.addingTimeInterval(86_400),
                         durationSeconds: 45 * 60)
        if let first = editor.exercises.first, let set = first.sets.first {
            editor.updateSet(exerciseId: first.id, setId: set.id, weight: 123, reps: 9)
            editor.toggleWarmup(exerciseId: first.id, setId: set.id)
            // Delete the last set, then add one: the survivor pattern proves
            // both (the new set copies the new last set, not the deleted one).
            if let last = first.sets.last, first.sets.count > 1 {
                editor.deleteSet(exerciseId: first.id, setId: last.id)
            }
            editor.addSet(exerciseId: first.id)
        }
        editor.moveExercises(fromOffsets: IndexSet(integer: editor.exercises.count - 1), toOffset: 0)
        if editor.exercises.count > 2, let last = editor.exercises.last {
            editor.removeExercise(exerciseId: last.id)
        }
        var present = Set(editor.exercises.map(\.exerciseId))
        if let candidate = model.exercises.first(where: { !present.contains($0.id) }),
           let target = editor.exercises.last {
            editor.replaceExercise(itemId: target.id, exerciseId: candidate.id, name: candidate.name,
                                   restSeconds: nil, baseline: nil, repBaseline: nil,
                                   previous: model.previousWorkingSets(exerciseId: candidate.id))
        }
        present = Set(editor.exercises.map(\.exerciseId))
        if let extra = model.exercises.first(where: { !present.contains($0.id) }) {
            editor.addExercise(exerciseId: extra.id, name: extra.name, restSeconds: nil,
                               baseline: nil, repBaseline: nil,
                               previous: model.previousWorkingSets(exerciseId: extra.id))
        }
        editor.flushPendingSaves()
        do { try await Task.sleep(for: .seconds(4)) } catch { return }
        dismiss()
    }
    #endif
}
