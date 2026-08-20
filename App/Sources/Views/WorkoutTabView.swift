import FitnessKit
import SwiftUI

struct WorkoutTabView: View {
    @Environment(AppModel.self) private var model
    @Environment(WorkoutSessionModel.self) private var session

    enum EditorTarget: Identifiable {
        case new
        case edit(TemplateSummary)
        var id: String {
            switch self {
            case .new: "new"
            case .edit(let template): template.id
            }
        }
    }

    @State private var editorTarget: EditorTarget?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    if session.isActive {
                        ResumeCard { session.isPresented = true }
                    }

                    ForEach(model.templates) { template in
                        TemplateCard(template: template,
                                     lastDone: lastDone(template),
                                     canStart: !session.isActive && model.isReady) {
                            start(template)
                        } onOpen: {
                            editorTarget = .edit(template)
                        }
                    }

                    Button("+ New template") { editorTarget = .new }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                                .foregroundStyle(Theme.inkTertiary.opacity(0.6)))

                    if !session.isActive {
                        Button("Start an empty workout") { start(nil) }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .padding(.top, 6)
                            .disabled(!model.isReady)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 24)
            }
            .appBackground()
            .navigationTitle("Workout")
        }
        .sheet(item: $editorTarget) { target in
            switch target {
            case .new: TemplateEditorView(existing: nil)
            case .edit(let template): TemplateEditorView(existing: template)
            }
        }
        #if DEBUG
        .task { await runScreenshotHooks() }
        #endif
    }

    #if DEBUG
    /// Screenshot/dev hooks driven by SIMCTL_CHILD_* env vars: SEED_TEMPLATE
    /// creates a template from the latest workout; START_WORKOUT also starts it
    /// and completes the first set; SHOW_FINISH opens the finish sheet.
    private func runScreenshotHooks() async {
        let env = ProcessInfo.processInfo.environment
        guard env["SEED_TEMPLATE"] != nil || env["START_WORKOUT"] != nil else { return }
        while !model.isReady {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if model.templates.isEmpty, let db = model.db,
           let latest = model.monthSections.first?.workouts.first {
            let drafts = latest.exercises.map { exercise in
                TemplateStore.ItemDraft(exerciseId: exercise.exerciseId,
                                        restSeconds: exercise.restSeconds
                                            ?? model.lastRestByExerciseId[exercise.exerciseId],
                                        targetSetCount: max(exercise.sets.count, 1))
            }
            try? TemplateStore.save(name: "Push Day", items: drafts, into: db)
            try? await model.reload()
        }
        guard env["START_WORKOUT"] != nil else { return }
        if !session.isActive, let template = model.templates.first {
            start(template)
            try? await Task.sleep(for: .milliseconds(500))
            if let exercise = session.exercises.first, let set = exercise.sets.first {
                session.toggleComplete(exerciseId: exercise.id, setId: set.id)
            }
        } else {
            session.isPresented = true
        }
    }
    #endif

    private func start(_ template: TemplateSummary?) {
        // Starting before the database is ready would create a phantom
        // session that silently loses everything logged into it.
        guard model.isReady else { return }
        session.start(template: template,
                      name: template?.name ?? WorkoutNames.random(),
                      baselines: model.bestE1RMByExerciseId,
                      repBaselines: model.bestRepsByExerciseId,
                      exerciseNames: model.exerciseNames)
        session.isPresented = true
    }

    private func lastDone(_ template: TemplateSummary) -> Date? {
        model.monthSections.first?.workouts.first { $0.name == template.name }?.startedAt
            ?? model.monthSections.flatMap(\.workouts).first { $0.name == template.name }?.startedAt
    }
}

private struct ResumeCard: View {
    @Environment(WorkoutSessionModel.self) private var session
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Workout in progress")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.75))
                        .textCase(.uppercase)
                        .kerning(0.6)
                    Text(session.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("\(session.completedSets) of \(session.totalSets) sets done")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.8))
                        .monospacedDigit()
                }
                Spacer()
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Theme.accent.opacity(0.35), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
    }
}

private struct TemplateCard: View {
    let template: TemplateSummary
    let lastDone: Date?
    let canStart: Bool
    let onStart: () -> Void
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(template.name)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    if canStart {
                        Button("Start", action: onStart)
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(Theme.accent, in: Capsule())
                    }
                }
                Text(meta)
                    .font(.caption)
                    .foregroundStyle(Theme.inkTertiary)
                Text(template.items.map(\.exerciseName).joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
                    .lineLimit(2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
        .buttonStyle(.plain)
    }

    private var meta: String {
        var parts = ["\(template.items.count) exercises"]
        if let lastDone {
            parts.append("last done \(lastDone.formatted(.relative(presentation: .named)))")
        }
        return parts.joined(separator: " · ")
    }
}
