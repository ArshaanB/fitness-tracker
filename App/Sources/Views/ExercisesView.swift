import FitnessKit
import SwiftUI

struct ExercisesView: View {
    @Environment(AppModel.self) private var model
    @State private var search = ""
    @State private var path = NavigationPath()
    @State private var alphabetical = false

    private var filtered: [ExerciseHistory] {
        var list = model.exercises  // already sorted by recency
        if alphabetical {
            list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        guard !search.isEmpty else { return list }
        return list.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack(path: $path) {
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.snappy) { alphabetical.toggle() }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.up.arrow.down")
                            Text(alphabetical ? "A–Z" : "Recent")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(Theme.accent.opacity(0.09), in: Capsule())
                    }
                }
            }
            .searchable(text: $search, prompt: "Search exercises")
            .navigationDestination(for: String.self) { exerciseId in
                if let exercise = model.exercises.first(where: { $0.id == exerciseId }) {
                    ExerciseDetailView(exercise: exercise)
                }
            }
            .onChange(of: model.isReady) { _, ready in
                #if DEBUG
                // Screenshot/dev hook: SIMCTL_CHILD_OPEN_EXERCISE="Bench Press"
                if ready, let name = ProcessInfo.processInfo.environment["OPEN_EXERCISE"],
                   let exercise = model.exercises.first(where: {
                       $0.name.localizedCaseInsensitiveContains(name)
                   }) {
                    path.append(exercise.id)
                }
                #endif
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
