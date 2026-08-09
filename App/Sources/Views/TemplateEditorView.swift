import FitnessKit
import SwiftUI

struct TemplateEditorView: View {
    let existing: TemplateSummary?

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    struct Draft: Identifiable {
        let id = UUID()
        var exerciseId: String
        var name: String
        var sets: Int
        var restSeconds: Int?
    }

    @State private var name = ""
    @State private var items: [Draft] = []
    @State private var showPicker = false
    @State private var loaded = false

    static let restOptions: [Int?] = [nil, 30, 45, 60, 75, 90, 120, 150, 180, 240, 300]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Template name", text: $name)
                        .font(.body.weight(.semibold))
                }

                Section("Exercises") {
                    ForEach($items) { $item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.name).font(.subheadline.weight(.semibold))
                            HStack(spacing: 14) {
                                Stepper("\(item.sets) sets", value: $item.sets, in: 1...10)
                                    .font(.footnote)
                                    .fixedSize()
                                Spacer()
                                Menu {
                                    ForEach(Array(Self.restOptions.enumerated()), id: \.offset) { _, option in
                                        Button(restLabel(option)) { item.restSeconds = option }
                                    }
                                } label: {
                                    Text("rest \(restLabel(item.restSeconds))")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete { items.remove(atOffsets: $0) }
                    .onMove { items.move(fromOffsets: $0, toOffset: $1) }

                    Button("+ Add exercise") { showPicker = true }
                        .foregroundStyle(Theme.accent)
                }

                Section {
                    Text("Templates set the structure. Weights and reps aren't stored here — each workout starts from whatever you did last session.")
                        .font(.caption)
                        .foregroundStyle(Theme.inkTertiary)
                        .listRowBackground(Color.clear)
                } footer: {
                    if existing != nil {
                        Button("Delete template", role: .destructive) {
                            if let existing {
                                try? TemplateStore.delete(id: existing.id, from: model.db!)
                                model.refresh()
                            }
                            dismiss()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                    }
                }
            }
            .navigationTitle(existing == nil ? "New Template" : "Edit Template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || items.isEmpty)
                }
            }
            .sheet(isPresented: $showPicker) {
                ExercisePickerView { exercise in
                    let previousCount = model.previousWorkingSets(exerciseId: exercise.id).count
                    items.append(Draft(exerciseId: exercise.id,
                                       name: exercise.name,
                                       sets: previousCount > 0 ? previousCount : 3,
                                       restSeconds: model.lastRestByExerciseId[exercise.id] ?? 90))
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let existing {
                    name = existing.name
                    items = existing.items.map {
                        Draft(exerciseId: $0.exerciseId, name: $0.exerciseName,
                              sets: $0.targetSetCount, restSeconds: $0.restSeconds)
                    }
                }
            }
        }
    }

    private func restLabel(_ seconds: Int?) -> String {
        guard let seconds else { return "off" }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func save() {
        guard let db = model.db else { return }
        let drafts = items.map {
            TemplateStore.ItemDraft(exerciseId: $0.exerciseId,
                                    restSeconds: $0.restSeconds,
                                    targetSetCount: $0.sets)
        }
        try? TemplateStore.save(id: existing?.id, name: name, items: drafts, into: db)
        model.refresh()
        dismiss()
    }
}

/// Searchable exercise chooser used by the template editor and mid-workout add.
struct ExercisePickerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    let onPick: (ExerciseHistory) -> Void

    private var filtered: [ExerciseHistory] {
        guard !search.isEmpty else { return model.exercises }
        return model.exercises.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { exercise in
                Button {
                    onPick(exercise)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        Text("\(exercise.sessionCount) sessions")
                            .font(.caption)
                            .foregroundStyle(Theme.inkTertiary)
                    }
                }
            }
            .searchable(text: $search, prompt: "Search exercises")
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
