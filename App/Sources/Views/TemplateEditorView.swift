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
    @State private var showDeleteConfirm = false
    @State private var loaded = false

    static let restOptions: [Int?] = [nil, 30, 45, 60, 75, 90, 120, 150, 180, 240, 300]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Template name", text: $name)
                        .font(.body.weight(.semibold))
                }

                Section {
                    ForEach($items) { $item in
                        VStack(alignment: .leading, spacing: 9) {
                            Text(item.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                            HStack {
                                SetCountStepper(sets: $item.sets)
                                Spacer()
                                Menu {
                                    ForEach(Array(Self.restOptions.enumerated()), id: \.offset) { _, option in
                                        Button(restLabel(option)) { item.restSeconds = option }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "timer")
                                        Text(restLabel(item.restSeconds))
                                    }
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Theme.accent)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 6)
                                    .background(Theme.accent.opacity(0.09), in: Capsule())
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { items.remove(atOffsets: $0) }
                    .onMove { items.move(fromOffsets: $0, toOffset: $1) }

                    Button {
                        showPicker = true
                    } label: {
                        Label("Add exercise", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                } header: {
                    Text("Exercises")
                } footer: {
                    Text("Templates set the structure: swipe to remove, drag to reorder. Weights and reps aren't stored here; each workout starts from whatever you did last session.")
                }

                if existing != nil {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: {
                            Text("Delete Template")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .appBackground()
            .confirmationDialog("Delete this template?", isPresented: $showDeleteConfirm,
                                titleVisibility: .visible) {
                Button("Delete Template", role: .destructive) {
                    if let existing, let db = model.db {
                        try? TemplateStore.delete(id: existing.id, from: db)
                        model.refresh()
                    }
                    dismiss()
                }
            } message: {
                Text("Your logged workouts keep their history. Only the template goes away.")
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

    private struct SetCountStepper: View {
        @Binding var sets: Int

        var body: some View {
            HStack(spacing: 10) {
                HStack(spacing: 0) {
                    stepButton("minus", enabled: sets > 1) { sets -= 1 }
                    Text("\(sets)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.ink)
                        .monospacedDigit()
                        .frame(width: 30)
                    stepButton("plus", enabled: sets < 10) { sets += 1 }
                }
                .background(Color(red: 234 / 255, green: 239 / 255, blue: 247 / 255), in: Capsule())
                Text("sets")
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSecondary)
            }
        }

        private func stepButton(_ icon: String, enabled: Bool,
                                action: @escaping () -> Void) -> some View {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(enabled ? Theme.accent : Theme.inkTertiary.opacity(0.5))
                    .frame(width: 34, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(!enabled)
        }
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
