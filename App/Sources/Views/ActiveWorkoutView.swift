import AudioToolbox
import FitnessKit
import SwiftUI

/// The rest-done chime, shared by the in-app timer and the notification (the
/// notification only sounds in the background, so the app plays it itself
/// when the timer finishes on screen). Respects the silent switch.
enum RestChime {
    private static let soundID: SystemSoundID = {
        var id: SystemSoundID = 0
        if let url = Bundle.main.url(forResource: "rest_done", withExtension: "caf") {
            AudioServicesCreateSystemSoundID(url as CFURL, &id)
        }
        return id
    }()

    static func play() {
        AudioServicesPlaySystemSound(soundID)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

struct ActiveWorkoutView: View {
    @Environment(AppModel.self) private var model
    @Environment(WorkoutSessionModel.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var showFinish = false
    // Editor-only state (history editing).
    @State private var showDeleteConfirm = false
    @State private var showTiming = false
    @State private var nameDraft = ""
    @State private var showPicker = false
    @State private var showOptions = false
    @State private var showDiscardConfirm = false
    @State private var showStalePrompt = false
    @State private var historyExercise: ExerciseHistory?

    var body: some View {
        VStack(spacing: 0) {
            header
            if !session.isEditor {
                progressBar
            }
            // A native List, purely for its reorder machinery: .onMove runs
            // UIKit's collection-view drag under the hood — system lift,
            // smooth sibling sliding, haptics, and edge auto-scroll — none of
            // which a hand-rolled per-frame gesture reproduces without jitter.
            List {
                ForEach(session.exercises) { exercise in
                    ExerciseSessionCard(exercise: exercise) {
                        historyExercise = model.exercises.first { $0.id == exercise.exerciseId }
                    }
                    // Collapse everything the moment a reorder lift starts:
                    // uniform compact rows stop the hover swap from
                    // flip-flopping (the endless-vibration bug) and keep the
                    // lifted platter card-sized.
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.35)
                            .onEnded { _ in
                                withAnimation(.spring(duration: 0.25)) {
                                    session.expandedExerciseIds = []
                                }
                            })
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    // Zero insets so the drag platter hugs the card; margins
                    // and spacing come from the list itself instead.
                    .listRowInsets(EdgeInsets())
                }
                .onMove { source, destination in
                    session.moveExercises(fromOffsets: source, toOffset: destination)
                }

                Button("+ Add exercise") { showPicker = true }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
                    .moveDisabled(true)
            }
            .listStyle(.plain)
            .listRowSpacing(10)
            .scrollContentBackground(.hidden)
            .contentMargins(.horizontal, 14, for: .scrollContent)
            .contentMargins(.top, 6, for: .scrollContent)
            .contentMargins(.bottom, 110, for: .scrollContent)
            // Mid-gym one-handed use: drag the sheet down to tuck the keyboard
            // away instead of hunting for a lone tappable gap.
            .scrollDismissesKeyboard(.interactively)
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
        .sheet(isPresented: $showFinish) { FinishSheet(dismissWorkout: { session.isPresented = false }) }
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
                session.isPresented = false
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
                session.isPresented = false
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
            nameDraft = session.name
            if !session.isEditor, session.isStale, !UserDefaults.standard.bool(forKey: dismissKey) {
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
                    session.isPresented = false
                }
            }
            #endif
        }
        // A dense in-gym grid: cap text scaling rather than break the layout.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    /// Live session: minimize to the mini bar. Editor: the sheet is owned by
    /// whoever presented it, so plain dismiss.
    private func close() {
        if session.isEditor {
            dismiss()
        } else {
            session.isPresented = false
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Button {
                close()
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
                if session.isEditor {
                    // Editing history: the title is a text field, the clock
                    // chip becomes a tappable date/duration.
                    TextField("Workout name", text: $nameDraft)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.ink)
                        .submitLabel(.done)
                        .onChange(of: nameDraft) { _, new in session.rename(new) }
                        // A rejected rename reverts the model; keep the field honest.
                        .onChange(of: session.name) { _, new in
                            if nameDraft != new { nameDraft = new }
                        }
                    Button {
                        showTiming = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "calendar")
                            Text(session.startedAt.formatted(.dateTime.month(.abbreviated).day()))
                            Text(session.startedAt.formatted(.dateTime.hour().minute()))
                            Text("·")
                            Text(Format.duration(session.durationSeconds))
                                .monospacedDigit()
                        }
                        .lineLimit(1)
                        .fixedSize()
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Theme.accent.opacity(0.09), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .sheet(isPresented: $showTiming) {
                        WorkoutTimingSheet(startedAt: session.startedAt,
                                           durationSeconds: session.durationSeconds) { start, duration in
                            session.setTiming(startedAt: start, durationSeconds: duration)
                        }
                    }
                } else {
                    // One line always: a wrapped title makes the whole header
                    // tall and crowds the sheet's grab handle.
                    Text(session.name)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    ElapsedChip(since: session.startedAt)
                }
            }
            Spacer()
            IntensityRing(ratio: session.isEditor ? session.completedIntensity : session.sessionIntensity,
                          size: 34, isRecord: session.sessionIsRecord)
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
                if session.isEditor {
                    Button("Delete Workout", role: .destructive) { showDeleteConfirm = true }
                } else {
                    Button("Discard Workout", role: .destructive) { showDiscardConfirm = true }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Couldn't save", isPresented: .init(
                get: { session.editError != nil },
                set: { if !$0 { session.editError = nil } })) {
                Button("OK") { session.editError = nil }
            } message: {
                Text(session.editError ?? "")
            }
            .alert("Delete this workout?", isPresented: $showDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    if let id = session.workoutId { model.deleteWorkout(id: id) }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Every set from \(session.name) will be removed. Records and charts recompute without it.")
            }
            Button(session.isEditor ? "Done" : "Finish") {
                if session.isEditor { close() } else { showFinish = true }
            }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(Theme.accent, in: Capsule())
                .shadow(color: Theme.accent.opacity(0.3), radius: 6, y: 2)
        }
        .padding(.horizontal, 18)
        // Breathing room below the sheet's grab handle.
        .padding(.top, 22)
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
    @State private var showRestPicker = false
    @State private var pendingReplace = false

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
                        Image(systemName: "ellipsis")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.inkSecondary)
                            .frame(width: 30, height: 30)
                            .background(Theme.inkTertiary.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Options for \(exercise.name)")
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
            .sheet(isPresented: $showRemoveConfirm, onDismiss: {
                // Present the picker only after the options sheet is fully
                // gone; stacking the two mid-transition drops the second.
                if pendingReplace {
                    pendingReplace = false
                    showReplacePicker = true
                }
            }) {
                ExerciseOptionsSheet(name: exercise.name,
                                     onReplace: { pendingReplace = true },
                                     onRemove: {
                    withAnimation(.spring(duration: 0.3)) {
                        session.removeExercise(exerciseId: exercise.id)
                    }
                })
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
                        if !session.isEditor {
                        Button {
                            showRestPicker = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "timer")
                                Text("Rest \(RestPickerSheet.label(exercise.restSeconds))")
                                    .monospacedDigit()
                            }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.inkSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Theme.inkTertiary.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .sheet(isPresented: $showRestPicker) {
                            RestPickerSheet(title: "Rest Timer", subtitle: exercise.name,
                                            initial: exercise.restSeconds) { seconds in
                                session.setRest(itemId: exercise.id, seconds: seconds)
                            }
                        }
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
        if session.isEditor {
            let working = exercise.sets.filter { !$0.isWarmup }.count
            let warmups = exercise.sets.count - working
            return warmups > 0 ? "\(working) sets · \(warmups) warm-up" : "\(working) sets"
        }
        var parts = ["\(exercise.completedCount) of \(exercise.sets.count) sets"]
        if let rest = exercise.restSeconds {
            parts.append("Rest \(String(format: "%d:%02d", rest / 60, rest % 60))")
        }
        return parts.joined(separator: " · ")
    }
}

private struct SetColumnHeaders: View {
    @Environment(WorkoutSessionModel.self) private var session

    var body: some View {
        HStack(spacing: 6) {
            Text("SET").frame(width: 30)
            Text(session.isEditor ? "" : "PREVIOUS").frame(maxWidth: .infinity, alignment: .leading)
            Text(Format.unitLabel.uppercased()).frame(width: 74)
            Text("REPS").frame(width: 56)
            Color.clear.frame(width: 28)
            if !session.isEditor {
                Color.clear.frame(width: 44)
            }
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
    /// Swipe actions: how far the row is dragged left; -trayWidth is "open".
    @State private var swipeOffset: CGFloat = 0
    @State private var showSetRest = false
    /// Axis decided once per gesture. The old per-frame dominance check froze
    /// the row whenever a drag went momentarily diagonal — that was the jank.
    @State private var dragLockedHorizontal: Bool?
    /// Offset captured when the gesture starts. Anchoring each frame to THIS
    /// (not the live swipeOffset, which the gesture itself mutates) is what
    /// makes the row track the finger 1:1 instead of teleporting a tray-width
    /// on the second frame.
    @State private var dragStartOffset: CGFloat = 0

    /// Width of the revealed swipe-action tray (timer + delete).
    private static let trayWidth: CGFloat = 128
    /// Dragged past this, releasing deletes the set (Mail-style full swipe).
    private static let deleteDistance: CGFloat = 210

    private var inFullSwipe: Bool { swipeOffset < -Self.deleteDistance }

    var body: some View {
        ZStack(alignment: .trailing) {
            // Actions sit behind the row and are progressively uncovered as
            // it slides; the container clips so nothing spills out of the card.
            HStack(spacing: 6) {
                if !inFullSwipe {
                    if session.isEditor {
                        // Editing history: the tray's second action marks the
                        // set as a warm-up (excluded from records) or back.
                        Button {
                            withAnimation(.spring(duration: 0.25)) { swipeOffset = 0 }
                            session.toggleWarmup(exerciseId: exercise.id, setId: set.id)
                        } label: {
                            Text("W")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 58)
                                .frame(maxHeight: .infinity)
                                .background(set.isWarmup ? Theme.ringMid : Theme.inkSecondary,
                                            in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(set.isWarmup ? "Mark set \(set.position) as working set"
                                                         : "Mark set \(set.position) as warm-up")
                        .transition(.opacity)
                    } else {
                        Button {
                            withAnimation(.spring(duration: 0.25)) { swipeOffset = 0 }
                            showSetRest = true
                        } label: {
                            Image(systemName: "timer")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 58)
                                .frame(maxHeight: .infinity)
                                .background(set.restSeconds != nil ? Theme.accent : Theme.inkSecondary,
                                            in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Rest timer for set \(set.position)")
                        .transition(.opacity)
                    }
                }
                Button {
                    deleteSet()
                } label: {
                    // Past the full-swipe point the trash grows to fill the
                    // whole revealed width — the cue that release will delete.
                    Image(systemName: "trash.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: inFullSwipe ? max(58, -swipeOffset - 6) : 58)
                        .frame(maxHeight: .infinity)
                        .background(Theme.ringLow, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete set \(set.position)")
            }
            .opacity(min(1, -swipeOffset / 50))
            .animation(.spring(duration: 0.22), value: inFullSwipe)

            rowContent
                .offset(x: swipeOffset)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    // Lock the axis on the first movement and keep it for the
                    // whole gesture: horizontal follows the finger 1:1,
                    // vertical is left entirely to the scroll view.
                    if dragLockedHorizontal == nil {
                        dragLockedHorizontal =
                            abs(value.translation.width) > abs(value.translation.height)
                        dragStartOffset = swipeOffset
                    }
                    guard dragLockedHorizontal == true else { return }
                    swipeOffset = min(0, dragStartOffset + value.translation.width)
                }
                .onEnded { _ in
                    defer { dragLockedHorizontal = nil }
                    guard dragLockedHorizontal == true else { return }
                    if inFullSwipe {
                        deleteSet()
                    } else {
                        withAnimation(.spring(duration: 0.28, bounce: 0.12)) {
                            swipeOffset = swipeOffset < -Self.trayWidth / 2 ? -Self.trayWidth : 0
                        }
                    }
                })
        .onTapGesture {
            if swipeOffset < 0 {
                withAnimation(.spring(duration: 0.25)) { swipeOffset = 0 }
            }
        }
        .sheet(isPresented: $showSetRest) {
            RestPickerSheet(title: "Rest After Set \(set.position)",
                            subtitle: "\(exercise.name) — overrides this exercise's rest for this set only.",
                            initial: set.restSeconds ?? exercise.restSeconds) { seconds in
                session.setSetRest(exerciseId: exercise.id, setId: set.id, seconds: seconds)
            }
        }
    }

    /// Mail's delete is two phases: the row first slides fully off-screen,
    /// THEN it leaves the model so the gap animates closed. Removing it in one
    /// step just blinks the row away.
    private func deleteSet() {
        withAnimation(.easeIn(duration: 0.2)) {
            swipeOffset = -UIScreen.main.bounds.width
        }
        let exerciseId = exercise.id
        let setId = set.id
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            withAnimation(.spring(duration: 0.32)) {
                session.deleteSet(exerciseId: exerciseId, setId: setId)
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 6) {
            Text(set.isWarmup ? "W" : "\(set.position)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(set.isWarmup ? Theme.ringMid : Theme.inkSecondary)
                .frame(width: 30)
                .monospacedDigit()
                // Tiny cue that this set carries its own rest timer.
                .overlay(alignment: .topTrailing) {
                    if set.restSeconds != nil {
                        Image(systemName: "timer")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Theme.accent)
                            .offset(x: 1, y: -1)
                    }
                }

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
                .background(set.completed && !session.isEditor ? .clear
                                : Color(red: 234 / 255, green: 239 / 255, blue: 247 / 255),
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
                .background(set.completed && !session.isEditor ? .clear
                                : Color(red: 234 / 255, green: 239 / 255, blue: 247 / 255),
                            in: RoundedRectangle(cornerRadius: 9))
                .frame(width: 56)
                .accessibilityLabel("Repetitions")
                .onChange(of: repsText) { _, text in
                    session.updateSet(exerciseId: exercise.id, setId: set.id,
                                      weight: set.weight, reps: Int(text))
                }

            IntensityRing(ratio: ratio, size: 24, isRecord: (ratio ?? 0) > 1)
                .frame(width: 28)

            if !session.isEditor {
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
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(set.completed && !session.isEditor
                        ? Color(red: 237 / 255, green: 249 / 255, blue: 241 / 255) : .clear,
                    in: RoundedRectangle(cornerRadius: 10))
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

/// Full-width bottom sheet with the actions for one exercise card.
private struct ExerciseOptionsSheet: View {
    let name: String
    let onReplace: () -> Void
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(name)
                .font(.headline)
                .foregroundStyle(Theme.ink)
            VStack(spacing: 10) {
                Button {
                    onReplace()
                    dismiss()
                } label: {
                    Label("Replace Exercise", systemImage: "arrow.triangle.2.circlepath")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
                }
                Button {
                    onRemove()
                    dismiss()
                } label: {
                    Label("Remove Exercise", systemImage: "trash")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.ringLow)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.ringLow.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                }
            }
            .buttonStyle(.plain)
            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .font(.body.weight(.medium))
                    .foregroundStyle(Theme.inkSecondary)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(216)])
        .presentationBackground(Color(red: 245 / 255, green: 247 / 255, blue: 251 / 255))
    }
}

/// History editor: when the workout happened and how long it took.
struct WorkoutTimingSheet: View {
    let startedAt: Date
    let durationSeconds: Int
    let onSave: (Date, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var start = Date()
    @State private var hours = 1
    @State private var minutes = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 6) {
                DatePicker("Started", selection: $start, displayedComponents: [.date, .hourAndMinute])
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 22)
                    .padding(.top, 8)
                Text("DURATION")
                    .font(.system(size: 10.5, weight: .semibold))
                    .kerning(0.5)
                    .foregroundStyle(Theme.inkTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22)
                HStack(spacing: 0) {
                    Picker("Hours", selection: $hours) {
                        ForEach(0..<13, id: \.self) { Text("\($0) hr").tag($0) }
                    }
                    .pickerStyle(.wheel)
                    Picker("Minutes", selection: $minutes) {
                        ForEach(0..<60, id: \.self) { Text("\($0) min").tag($0) }
                    }
                    .pickerStyle(.wheel)
                }
                .frame(height: 150)
            }
            .navigationTitle("Date & Duration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(start, hours * 3600 + minutes * 60)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                start = startedAt
                hours = min(durationSeconds / 3600, 12)
                minutes = (durationSeconds % 3600) / 60
            }
        }
        .presentationDetents([.height(340)])
    }
}

/// Apple-timer-style rest chooser: minute/second wheels in a compact sheet.
/// Used per-exercise and for the workout-wide default.
struct RestPickerSheet: View {
    let title: String
    let subtitle: String?
    let initial: Int?
    let onSet: (Int?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var minutes = 1
    @State private var seconds = 30

    static func label(_ seconds: Int?) -> String {
        guard let seconds, seconds > 0 else { return "Off" }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 4) {
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                HStack(spacing: 0) {
                    Picker("Minutes", selection: $minutes) {
                        ForEach(0..<11, id: \.self) { Text("\($0) min").tag($0) }
                    }
                    .pickerStyle(.wheel)
                    Picker("Seconds", selection: $seconds) {
                        ForEach(Array(stride(from: 0, through: 55, by: 5)), id: \.self) {
                            Text("\($0) sec").tag($0)
                        }
                    }
                    .pickerStyle(.wheel)
                }
                .frame(height: 175)
                Button("Turn Off Rest Timer") {
                    onSet(nil)
                    dismiss()
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.ringLow)
                .padding(.bottom, 6)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Set") {
                        let total = minutes * 60 + seconds
                        onSet(total == 0 ? nil : total)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                let start = initial ?? 90
                minutes = min(start / 60, 10)
                seconds = min((start % 60) / 5 * 5, 55)
            }
        }
        .presentationDetents([.height(330)])
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
                    if let next = rest.nextText {
                        Text("Next: \(next)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                            .monospacedDigit()
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
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
                        // The timer ran out on screen: chime here, since the
                        // scheduled notification stays silent in-foreground.
                        RestChime.play()
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
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Workout complete")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(Theme.ink)
                            Text("\(session.name) · \(Date().formatted(.dateTime.weekday(.wide).month().day()))")
                                .font(.footnote)
                                .foregroundStyle(Theme.inkSecondary)
                        }
                        Spacer()
                        // The workout's score: completed sets vs your records,
                        // same colors as the live ring; rainbow means PR day.
                        if let intensity = session.completedIntensity {
                            VStack(spacing: 4) {
                                IntensityRing(ratio: intensity, size: 52,
                                              isRecord: session.sessionHasPR && intensity >= 0.9)
                                Text("\(Int((intensity * 100).rounded()))%")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Theme.inkSecondary)
                                    .monospacedDigit()
                            }
                        }
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
