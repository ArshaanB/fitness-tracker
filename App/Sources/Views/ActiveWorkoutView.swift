import FitnessKit
import SwiftUI

struct ActiveWorkoutView: View {
    @Environment(AppModel.self) private var model
    @Environment(WorkoutSessionModel.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var showFinish = false
    @State private var showPicker = false
    @State private var showOptions = false
    @State private var showRestForAll = false
    @State private var showDiscardConfirm = false
    @State private var showStalePrompt = false
    @State private var historyExercise: ExerciseHistory?
    @State private var draggingExerciseId: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            progressBar
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(session.exercises) { exercise in
                        ExerciseSessionCard(exercise: exercise) {
                            historyExercise = model.exercises.first { $0.id == exercise.exerciseId }
                        }
                        .onDrag {
                            draggingExerciseId = exercise.id
                            return NSItemProvider(object: exercise.id as NSString)
                        }
                        .onDrop(of: [.text], delegate: ExerciseDropDelegate(
                            targetId: exercise.id, dragging: $draggingExerciseId,
                            session: session))
                        .opacity(draggingExerciseId == exercise.id ? 0.55 : 1)
                    }
                    Button("+ Add exercise") { showPicker = true }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.vertical, 10)
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 120)
            }
            // Mid-gym one-handed use: drag the sheet down to tuck the keyboard
            // away instead of hunting for a lone tappable gap.
            .scrollDismissesKeyboard(.interactively)
            // Catch-all for drags released between cards: reordering already
            // persisted on hover, this just clears the dimmed dragged card.
            .onDrop(of: [.text], isTargeted: nil) { _ in
                draggingExerciseId = nil
                return true
            }
        }
        .appBackground()
        .overlay(alignment: .bottom) {
            if session.rest != nil {
                RestPill()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    // Stay at the screen bottom; riding the keyboard covers
                    // the very set row being edited.
                    .ignoresSafeArea(.keyboard, edges: .bottom)
            }
        }
        .animation(.spring(duration: 0.35), value: session.rest?.endDate)
        .sheet(isPresented: $showFinish) { FinishSheet(dismissWorkout: { dismiss() }) }
        .sheet(item: $historyExercise) { exercise in
            NavigationStack {
                ExerciseDetailView(exercise: exercise)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { historyExercise = nil }
                        }
                    }
            }
        }
        .sheet(isPresented: $showPicker) {
            ExercisePickerView { picked in
                for exercise in picked {
                    session.addExercise(exerciseId: exercise.id,
                                        name: exercise.name,
                                        restSeconds: model.lastRestByExerciseId[exercise.id],
                                        baseline: model.bestE1RMByExerciseId[exercise.id],
                                        repBaseline: model.bestRepsByExerciseId[exercise.id],
                                        previous: model.previousWorkingSets(exerciseId: exercise.id))
                }
            }
        }
        .alert("Discard this workout?", isPresented: $showDiscardConfirm) {
            Button("Discard", role: .destructive) {
                session.discard()
                model.refresh()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every set from this session will be deleted. Your past workouts are untouched.")
        }
        .confirmationDialog("This workout has been sitting for a while.",
                            isPresented: $showStalePrompt, titleVisibility: .visible) {
            Button("Finish it") { showFinish = true }
            Button("Discard it", role: .destructive) {
                session.discard()
                model.refresh()
                dismiss()
            }
            Button("Keep going", role: .cancel) {
                if let id = session.workoutId {
                    UserDefaults.standard.set(true, forKey: "staleDismissed-\(id)")
                }
            }
        }
        .onAppear {
            // Ask once per session about staleness; "Keep going" shouldn't
            // re-prompt on every reopen.
            let dismissKey = "staleDismissed-\(session.workoutId ?? "")"
            if session.isStale && !UserDefaults.standard.bool(forKey: dismissKey) {
                showStalePrompt = true
            }
            #if DEBUG
            if ProcessInfo.processInfo.environment["SHOW_FINISH"] != nil {
                showFinish = true
            }
            // Full-cycle test hook: finish the workout without a tap.
            if ProcessInfo.processInfo.environment["AUTO_FINISH"] != nil {
                Task {
                    do { try await Task.sleep(for: .seconds(3)) } catch { return }
                    session.finish()
                    model.refresh()
                    dismiss()
                }
            }
            #endif
        }
        // A dense in-gym grid: cap text scaling rather than break the layout.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    private var header: some View {
        HStack(alignment: .center) {
            Button {
                session.isPresented = false
            } label: {
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(width: 36, height: 36)
                    .background(.white, in: Circle())
                    .shadow(color: Color(red: 16 / 255, green: 38 / 255, blue: 74 / 255).opacity(0.08),
                            radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Minimize workout")
            VStack(alignment: .leading, spacing: 4) {
                Text(session.name)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                ElapsedChip(since: session.startedAt)
            }
            Spacer()
            IntensityRing(ratio: session.sessionIntensity, size: 34,
                          isRecord: session.sessionIsRecord)
                .padding(.trailing, 6)
            Button {
                showOptions = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(width: 36, height: 36)
                    .background(.white, in: Circle())
                    .shadow(color: Color(red: 16 / 255, green: 38 / 255, blue: 74 / 255).opacity(0.08),
                            radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 2)
            .confirmationDialog("Workout options", isPresented: $showOptions) {
                Button("Add Exercise") { showPicker = true }
                Button("Rest Timer for All Exercises…") { showRestForAll = true }
                Button("Discard Workout", role: .destructive) { showDiscardConfirm = true }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Rest timer for all exercises",
                                isPresented: $showRestForAll, titleVisibility: .visible) {
                Button("Off") { session.setRestForAll(seconds: nil) }
                ForEach(RestMenu.options, id: \.self) { seconds in
                    Button(RestMenu.label(seconds)) { session.setRestForAll(seconds: seconds) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Applies to every exercise here, and to ones you add later. You can still change any single exercise afterward.")
            }
            Button("Finish") { showFinish = true }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(Theme.accent, in: Capsule())
                .shadow(color: Theme.accent.opacity(0.3), radius: 6, y: 2)
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(red: 223 / 255, green: 230 / 255, blue: 240 / 255))
                Capsule()
                    .fill(LinearGradient(colors: [Theme.accent, Color(red: 77 / 255, green: 141 / 255, blue: 1)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: proxy.size.width * progress)
                    .animation(.easeOut(duration: 0.3), value: progress)
            }
        }
        .frame(height: 4)
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
    }

    private var progress: Double {
        session.totalSets > 0 ? Double(session.completedSets) / Double(session.totalSets) : 0
    }
}

struct ElapsedChip: View {
    let since: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = Int(context.date.timeIntervalSince(since))
            HStack(spacing: 5) {
                Circle().fill(Theme.accent).frame(width: 6, height: 6)
                Text(Format.duration(max(elapsed, 0)))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Theme.accent.opacity(0.09), in: Capsule())
        }
    }
}

// MARK: - Exercise card

private struct ExerciseSessionCard: View {
    @Environment(AppModel.self) private var model
    @Environment(WorkoutSessionModel.self) private var session
    let exercise: WorkoutSessionModel.SessionExercise
    let onShowHistory: () -> Void

    @State private var showRemoveConfirm = false
    @State private var showReplacePicker = false

    private var expanded: Bool { session.expandedExerciseIds.contains(exercise.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(meta)
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                        .monospacedDigit()
                }
                Spacer()
                if expanded {
                    Button {
                        showRemoveConfirm = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.inkSecondary)
                            .frame(width: 30, height: 30)
                            .background(Theme.inkTertiary.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(exercise.name) from workout")
                }
                Button(action: onShowHistory) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 30, height: 30)
                        .background(Theme.accent.opacity(0.09), in: Circle())
                }
                .buttonStyle(.plain)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkTertiary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            }
            .padding(14)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(duration: 0.3)) {
                    if expanded {
                        session.expandedExerciseIds.remove(exercise.id)
                    } else {
                        session.expandedExerciseIds.insert(exercise.id)
                    }
                }
            }
            .contextMenu {
                Button("Remove exercise", role: .destructive) {
                    showRemoveConfirm = true
                }
            }
            .confirmationDialog("\(exercise.name)",
                                isPresented: $showRemoveConfirm, titleVisibility: .visible) {
                Button("Replace Exercise…") { showReplacePicker = true }
                Button("Remove Exercise", role: .destructive) {
                    withAnimation(.spring(duration: 0.3)) {
                        session.removeExercise(exerciseId: exercise.id)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Either way, its sets leave this workout only. Past workouts are untouched.")
            }
            .sheet(isPresented: $showReplacePicker) {
                ExercisePickerView(singleSelect: true, title: "Replace with…") { picked in
                    guard let new = picked.first else { return }
                    withAnimation(.spring(duration: 0.3)) {
                        session.replaceExercise(itemId: exercise.id,
                                                exerciseId: new.id,
                                                name: new.name,
                                                restSeconds: model.lastRestByExerciseId[new.id],
                                                baseline: model.bestE1RMByExerciseId[new.id],
                                                repBaseline: model.bestRepsByExerciseId[new.id],
                                                previous: model.previousWorkingSets(exerciseId: new.id))
                    }
                }
            }

            if expanded {
                VStack(spacing: 4) {
                    SetColumnHeaders()
                    ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                        SetRow(exercise: exercise, set: set,
                               previous: index < exercise.previous.count ? exercise.previous[index] : nil)
                    }
                    HStack {
                        Button("+ Add set") { session.addSet(exerciseId: exercise.id) }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                        Spacer()
                        RestMenu(current: exercise.restSeconds) { seconds in
                            session.setRest(itemId: exercise.id, seconds: seconds)
                        }
                    }
                    .padding(.top, 6)
                    .padding(.bottom, 4)
                    .padding(.horizontal, 4)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .cardStyle()
    }

    private var meta: String {
        var parts = ["\(exercise.completedCount) of \(exercise.sets.count) sets"]
        if let rest = exercise.restSeconds {
            parts.append("Rest \(String(format: "%d:%02d", rest / 60, rest % 60))")
        }
        return parts.joined(separator: " · ")
    }
}

private struct SetColumnHeaders: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("SET").frame(width: 30)
            Text("PREVIOUS").frame(maxWidth: .infinity, alignment: .leading)
            Text(Format.unitLabel.uppercased()).frame(width: 74)
            Text("REPS").frame(width: 56)
            Color.clear.frame(width: 28)
            Color.clear.frame(width: 44)
        }
        .font(.system(size: 10.5, weight: .semibold))
        .kerning(0.5)
        .foregroundStyle(Theme.inkTertiary)
        .padding(.bottom, 2)
    }
}

private struct SetRow: View {
    @Environment(WorkoutSessionModel.self) private var session
    let exercise: WorkoutSessionModel.SessionExercise
    let set: WorkoutSessionModel.SessionSet
    let previous: LoadedSet?

    // Local text state: a get/set binding that reformats the model value on
    // every keystroke eats the decimal separator ("185." reformats to "185"),
    // making decimal weights untypable. The text is the source of truth while
    // editing; the model receives parsed values.
    @State private var weightText = ""
    @State private var repsText = ""

    var body: some View {
        HStack(spacing: 6) {
            Text(set.isWarmup ? "W" : "\(set.position)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(set.isWarmup ? Theme.ringMid : Theme.inkSecondary)
                .frame(width: 30)
                .monospacedDigit()

            Text(previousText)
                .font(.subheadline)
                .foregroundStyle(Theme.inkTertiary)
                .monospacedDigit()
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("", text: $weightText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .padding(.vertical, 7)
                .background(set.completed ? .clear : Color(red: 234 / 255, green: 239 / 255, blue: 247 / 255),
                            in: RoundedRectangle(cornerRadius: 9))
                .frame(width: 74)
                .accessibilityLabel("Weight in \(Format.unitLabel)")
                .onChange(of: weightText) { _, text in
                    // Format.weight rounds display to 0.1, so parsing it back
                    // shifts the stored value slightly; skip when the text is
                    // just the stored weight re-formatted (the onAppear seed).
                    if text == (set.weight.map { Format.weight($0) } ?? "") { return }
                    session.updateSet(exerciseId: exercise.id, setId: set.id,
                                      weight: Self.parseWeight(text).map { Format.unit.toStorage($0) },
                                      reps: set.reps)
                }

            TextField("", text: $repsText)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .padding(.vertical, 7)
                .background(set.completed ? .clear : Color(red: 234 / 255, green: 239 / 255, blue: 247 / 255),
                            in: RoundedRectangle(cornerRadius: 9))
                .frame(width: 56)
                .accessibilityLabel("Repetitions")
                .onChange(of: repsText) { _, text in
                    session.updateSet(exerciseId: exercise.id, setId: set.id,
                                      weight: set.weight, reps: Int(text))
                }

            IntensityRing(ratio: ratio, size: 24, isRecord: (ratio ?? 0) > 1)
                .frame(width: 28)

            Button {
                session.toggleComplete(exerciseId: exercise.id, setId: set.id)
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(set.completed ? .white : Theme.inkTertiary.opacity(0.55))
                    .frame(width: 44, height: 30)
                    .background(set.completed ? Theme.ringHigh : .white,
                                in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(set.completed ? .clear : Color(red: 213 / 255, green: 218 / 255, blue: 226 / 255),
                                      lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(set.completed ? "Mark set \(set.position) incomplete"
                                              : "Complete set \(set.position)")
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(set.completed ? Color(red: 237 / 255, green: 249 / 255, blue: 241 / 255) : .clear,
                    in: RoundedRectangle(cornerRadius: 10))
        .contextMenu {
            Button("Delete set", role: .destructive) {
                session.deleteSet(exerciseId: exercise.id, setId: set.id)
            }
        }
        .onAppear {
            weightText = set.weight.map { Format.weight($0) } ?? ""
            repsText = set.reps.map(String.init) ?? ""
        }
    }

    /// Accepts both "." and "," as decimal separators.
    static func parseWeight(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    private var previousText: String {
        guard let previous else { return "" }
        return Format.set(previous).replacingOccurrences(of: "×", with: " × ")
    }

    private var ratio: Double? {
        WorkoutSessionModel.setRatio(set, in: exercise)
    }
}

/// Reorders exercises live as a dragged card passes over its siblings.
private struct ExerciseDropDelegate: DropDelegate {
    let targetId: String
    @Binding var dragging: String?
    let session: WorkoutSessionModel

    func dropEntered(info: DropInfo) {
        guard let dragging else { return }
        withAnimation(.spring(duration: 0.3)) {
            session.reorderExercise(draggedId: dragging, over: targetId)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

/// Rest-duration chooser used per-exercise; the workout-wide dialog shares
/// its option list and labels.
struct RestMenu: View {
    static let options = [30, 45, 60, 75, 90, 120, 150, 180, 240, 300]

    static func label(_ seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "Off" }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    let current: Int?
    let onPick: (Int?) -> Void

    var body: some View {
        Menu {
            button(nil)
            ForEach(Self.options, id: \.self) { button($0) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "timer")
                Text("Rest \(Self.label(current))")
                    .monospacedDigit()
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.inkSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.inkTertiary.opacity(0.12), in: Capsule())
        }
    }

    private func button(_ seconds: Int?) -> some View {
        Button {
            onPick(seconds)
        } label: {
            if current == seconds {
                Label(Self.label(seconds), systemImage: "checkmark")
            } else {
                Text(Self.label(seconds))
            }
        }
    }
}

// MARK: - Rest pill

private struct RestPill: View {
    @Environment(WorkoutSessionModel.self) private var session

    var body: some View {
        if let rest = session.rest {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let remaining = max(0, Int(rest.endDate.timeIntervalSince(context.date).rounded()))
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("REST")
                                .font(.system(size: 10.5, weight: .semibold))
                                .kerning(0.5)
                                .foregroundStyle(.white.opacity(0.6))
                            Text(String(format: "%d:%02d", remaining / 60, remaining % 60))
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.white)
                                .monospacedDigit()
                        }
                        Spacer()
                        Button("−10s") { session.adjustRest(by: -10) }
                            .buttonStyle(RestAdjustStyle())
                        Button("+10s") { session.adjustRest(by: 10) }
                            .buttonStyle(RestAdjustStyle())
                        Button("Skip") { session.clearRest() }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 8)
                            .background(Theme.accent, in: Capsule())
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.15))
                            Capsule().fill(Theme.accent)
                                .frame(width: proxy.size.width * min(1, Double(remaining) / Double(max(rest.totalSeconds, 1))))
                        }
                    }
                    .frame(height: 3)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 10)
                .background(Theme.ink, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: Theme.ink.opacity(0.35), radius: 14, y: 6)
                .task(id: rest.endDate) {
                    let interval = rest.endDate.timeIntervalSinceNow
                    if interval > 0 {
                        try? await Task.sleep(for: .seconds(interval))
                    }
                    // ±10s restarts this task via the id change; the cancelled
                    // instance must not tear the pill down on its way out.
                    if !Task.isCancelled {
                        session.clearRest()
                    }
                }
            }
        }
    }
}

private struct RestAdjustStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .monospacedDigit()
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.14), in: Capsule())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

// MARK: - Finish sheet

private struct FinishSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(WorkoutSessionModel.self) private var session
    @Environment(SyncModel.self) private var sync
    @Environment(\.dismiss) private var dismiss
    let dismissWorkout: () -> Void

    var body: some View {
        let summary = session.finishSummary()
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Workout complete")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Theme.ink)
                        Text("\(session.name) · \(Date().formatted(.dateTime.weekday(.wide).month().day()))")
                            .font(.footnote)
                            .foregroundStyle(Theme.inkSecondary)
                    }

                    HStack(spacing: 10) {
                        stat(Format.duration(summary.duration), "Duration")
                        stat("\(Format.volume(summary.volume)) \(Format.unitLabel)", "Volume")
                        stat("\(summary.sets)", "Sets")
                    }

                    if summary.sets == 0 {
                        Text("No sets were completed, so this workout will be discarded rather than saved to history.")
                            .font(.footnote)
                            .foregroundStyle(Theme.inkSecondary)
                    }

                    if !summary.prs.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("NEW RECORDS")
                                .font(.system(size: 11, weight: .semibold))
                                .kerning(0.8)
                                .foregroundStyle(Theme.inkTertiary)
                            ForEach(summary.prs) { pr in
                                HStack(spacing: 12) {
                                    IntensityRing(ratio: 1, size: 26)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(pr.name)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(Theme.ink)
                                        Text("est. 1RM \(Format.wholeWeight(pr.e1RM)) \(Format.unitLabel)")
                                            .font(.caption)
                                            .foregroundStyle(Theme.inkSecondary)
                                            .monospacedDigit()
                                    }
                                    Spacer()
                                    if let previous = pr.previousBest {
                                        Text("+\(Format.wholeWeight(pr.e1RM - previous)) \(Format.unitLabel)")
                                            .font(.subheadline.weight(.bold))
                                            .foregroundStyle(Theme.ringHigh)
                                            .monospacedDigit()
                                    } else {
                                        Text("first record")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(Theme.inkTertiary)
                                    }
                                }
                                .padding(12)
                                .background(.white, in: RoundedRectangle(cornerRadius: 14))
                            }
                        }
                    }
                }
                .padding(22)
            }

            Button {
                session.finish()
                model.refresh()
                sync.pushSoon()
                dismiss()
                dismissWorkout()
            } label: {
                Text(summary.sets == 0 ? "Discard Workout" : "Finish Workout")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(summary.sets == 0 ? Theme.ringLow : Theme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color(red: 245 / 255, green: 247 / 255, blue: 251 / 255))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline).foregroundStyle(Theme.ink).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(Theme.inkSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
    }
}
