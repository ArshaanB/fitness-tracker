import FitnessKit
import SwiftUI

struct ActiveWorkoutView: View {
    @Environment(AppModel.self) private var model
    @Environment(WorkoutSessionModel.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var showFinish = false
    @State private var showPicker = false
    @State private var showDiscardConfirm = false
    @State private var showStalePrompt = false

    var body: some View {
        VStack(spacing: 0) {
            header
            progressBar
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(session.exercises) { exercise in
                        ExerciseSessionCard(exercise: exercise)
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
        }
        .appBackground()
        .overlay(alignment: .bottom) {
            if session.rest != nil {
                RestPill()
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: session.rest?.endDate)
        .sheet(isPresented: $showFinish) { FinishSheet(dismissWorkout: { dismiss() }) }
        .sheet(isPresented: $showPicker) {
            ExercisePickerView { exercise in
                session.addExercise(exerciseId: exercise.id,
                                    name: exercise.name,
                                    restSeconds: model.lastRestByExerciseId[exercise.id],
                                    baseline: model.bestE1RMByExerciseId[exercise.id],
                                    previous: model.previousWorkingSets(exerciseId: exercise.id))
            }
        }
        .confirmationDialog("Discard this workout?", isPresented: $showDiscardConfirm,
                            titleVisibility: .visible) {
            Button("Discard workout", role: .destructive) {
                session.discard()
                model.refresh()
                dismiss()
            }
        }
        .confirmationDialog("This workout has been sitting for a while.",
                            isPresented: $showStalePrompt, titleVisibility: .visible) {
            Button("Finish it") { showFinish = true }
            Button("Discard it", role: .destructive) {
                session.discard()
                model.refresh()
                dismiss()
            }
            Button("Keep going", role: .cancel) {}
        }
        .onAppear {
            showStalePrompt = session.isStale
            #if DEBUG
            if ProcessInfo.processInfo.environment["SHOW_FINISH"] != nil {
                showFinish = true
            }
            #endif
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.name)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.ink)
                ElapsedChip(since: session.startedAt)
            }
            Spacer()
            Menu {
                Button("Discard workout", role: .destructive) { showDiscardConfirm = true }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(Theme.inkSecondary)
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
    @Environment(WorkoutSessionModel.self) private var session
    let exercise: WorkoutSessionModel.SessionExercise

    private var expanded: Bool { session.expandedExerciseId == exercise.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(duration: 0.3)) {
                    session.expandedExerciseId = expanded ? nil : exercise.id
                }
            } label: {
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
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.inkTertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Remove exercise", role: .destructive) {
                    session.removeExercise(exerciseId: exercise.id)
                }
            }

            if expanded {
                VStack(spacing: 4) {
                    SetColumnHeaders()
                    ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                        SetRow(exercise: exercise, set: set,
                               previous: index < exercise.previous.count ? exercise.previous[index] : nil)
                    }
                    Button("+ Add set") { session.addSet(exerciseId: exercise.id) }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.top, 6)
                        .padding(.bottom, 4)
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
            parts.append("rest \(String(format: "%d:%02d", rest / 60, rest % 60))")
        }
        return parts.joined(separator: " · ")
    }
}

private struct SetColumnHeaders: View {
    var body: some View {
        HStack(spacing: 6) {
            Text("SET").frame(width: 30)
            Text("PREVIOUS").frame(maxWidth: .infinity, alignment: .leading)
            Text("LBS").frame(width: 74)
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

    @FocusState private var focused: Bool

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

            TextField("—", text: weightBinding)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .padding(.vertical, 7)
                .background(set.completed ? .clear : Color(red: 234 / 255, green: 239 / 255, blue: 247 / 255),
                            in: RoundedRectangle(cornerRadius: 9))
                .frame(width: 74)

            TextField("—", text: repsBinding)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .padding(.vertical, 7)
                .background(set.completed ? .clear : Color(red: 234 / 255, green: 239 / 255, blue: 247 / 255),
                            in: RoundedRectangle(cornerRadius: 9))
                .frame(width: 56)

            IntensityRing(ratio: ratio, size: 24)
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
    }

    private var previousText: String {
        guard let previous else { return "—" }
        return Format.set(previous).replacingOccurrences(of: "×", with: " × ")
    }

    private var ratio: Double? {
        guard let e1RM = set.e1RM, let baseline = exercise.baselineE1RM, baseline > 0 else { return nil }
        return e1RM / baseline
    }

    private var weightBinding: Binding<String> {
        Binding {
            set.weight.map { Format.weight($0) } ?? ""
        } set: { text in
            session.updateSet(exerciseId: exercise.id, setId: set.id,
                              weight: Double(text), reps: set.reps)
        }
    }

    private var repsBinding: Binding<String> {
        Binding {
            set.reps.map(String.init) ?? ""
        } set: { text in
            session.updateSet(exerciseId: exercise.id, setId: set.id,
                              weight: set.weight, reps: Int(text))
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
                            Text("REST · \(rest.exerciseName)")
                                .font(.system(size: 10.5, weight: .semibold))
                                .kerning(0.5)
                                .foregroundStyle(.white.opacity(0.6))
                                .lineLimit(1)
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
                    session.clearRest()
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
    @Environment(\.dismiss) private var dismiss
    let dismissWorkout: () -> Void

    var body: some View {
        let summary = session.finishSummary()
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
                stat("\(Format.volume(summary.volume)) lbs", "Volume")
                stat("\(summary.sets)", "Sets")
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
                                Text("est. 1RM \(Int(pr.e1RM)) lbs")
                                    .font(.caption)
                                    .foregroundStyle(Theme.inkSecondary)
                                    .monospacedDigit()
                            }
                            Spacer()
                            if let previous = pr.previousBest {
                                Text("+\(Int(pr.e1RM - previous)) lbs")
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

            Spacer()

            Button {
                session.finish()
                model.refresh()
                dismiss()
                dismissWorkout()
            } label: {
                Text("Finish Workout")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Theme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(22)
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
