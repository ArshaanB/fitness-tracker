import FitnessKit
import SwiftUI

struct ExercisesView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""

    private var filtered: [ExerciseHistory] {
        guard !search.isEmpty else { return model.exercises }
        return model.exercises.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(filtered) { exercise in
                        NavigationLink(value: exercise.id) {
                            ExerciseRow(exercise: exercise)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 24)
            }
            .appBackground()
            .navigationTitle("Exercises")
            .searchable(text: $search, prompt: "Search exercises")
            .navigationDestination(for: String.self) { exerciseId in
                if let exercise = model.exercises.first(where: { $0.id == exerciseId }) {
                    ExerciseDetailView(exercise: exercise)
                }
            }
        }
    }
}

private struct ExerciseRow: View {
    let exercise: ExerciseHistory

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Theme.inkTertiary)
                    .monospacedDigit()
            }
            Spacer()
            if let best = exercise.bestE1RM {
                Text("\(Int(best)) e1RM")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .monospacedDigit()
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.inkTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var subtitle: String {
        var parts = ["\(exercise.sessionCount) sessions"]
        if let last = exercise.lastDone {
            parts.append("last \(last.formatted(.relative(presentation: .named)))")
        }
        return parts.joined(separator: " · ")
    }
}
