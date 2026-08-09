import Charts
import FitnessKit
import SwiftUI
import UniformTypeIdentifiers

struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @Environment(SyncModel.self) private var sync

    @State private var showAuth = false
    @State private var showImporter = false
    @State private var importMessage: String?
    @State private var showWeightSheet = false
    @State private var scrubbedWeek: WeekBucket?
    @State private var scrubbedWeight: BodyWeightRecord?

    private var buckets: [WeekBucket] {
        WeeklyStats.weekBuckets(workoutsAscending: model.workoutsAscending, weeks: 12)
    }

    private var streak: Int {
        WeeklyStats.currentStreak(workoutsAscending: model.workoutsAscending, goal: model.weeklyGoal)
    }

    private var average: Double {
        WeeklyStats.averagePerWeek(workoutsAscending: model.workoutsAscending, weeks: 12)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    tiles
                    frequencyCard
                    bodyWeightCard
                    accountCard
                    settingsCard
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 24)
            }
            .appBackground()
            .navigationTitle("Profile")
            .sheet(isPresented: $showAuth) {
                AuthSheet()
            }
            .sheet(isPresented: $showWeightSheet) {
                LogWeightSheet(lastWeight: model.bodyWeights.last?.weight)
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
                if case .success(let url) = result {
                    Task { importMessage = await model.importStrongCSV(from: url) }
                }
            }
            .alert("Strong Import", isPresented: .init(
                get: { importMessage != nil },
                set: { if !$0 { importMessage = nil } })) {
                Button("OK") { importMessage = nil }
            } message: {
                Text(importMessage ?? "")
            }
        }
    }

    // MARK: - Tiles

    private var tiles: some View {
        HStack(spacing: 10) {
            let thisWeek = buckets.last?.workoutCount ?? 0
            tile("\(thisWeek)", "This week", color: goalColor(thisWeek))
            tile("\(streak) wks", "Streak at goal", color: Theme.ink)
            tile(String(format: "%.1f", average), "Avg / week", color: Theme.ink)
        }
    }

    private func tile(_ value: String, _ label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.weight(.bold)).foregroundStyle(color).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(Theme.inkSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func goalColor(_ count: Int) -> Color {
        switch WeeklyStats.goalZone(count: count, goal: model.weeklyGoal) {
        case .met: Theme.ringHigh
        case .close: Color(red: 1, green: 192 / 255, blue: 46 / 255)
        case .far: Color(red: 242 / 255, green: 140 / 255, blue: 13 / 255)
        case .missed: Theme.ringLow
        }
    }

    // MARK: - Frequency chart

    private var frequencyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Workouts per week").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                Spacer()
                Text("goal \(model.weeklyGoal)/wk · last 12 weeks")
                    .font(.caption)
                    .foregroundStyle(Theme.inkTertiary)
                    .monospacedDigit()
            }
            Chart {
                ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
                    BarMark(x: .value("Week", bucket.weekStart, unit: .weekOfYear),
                            y: .value("Workouts", max(Double(bucket.workoutCount), 0.12)),
                            width: .ratio(0.55))
                        .foregroundStyle(goalColor(bucket.workoutCount)
                            .opacity(index == buckets.count - 1 ? 0.45 : 0.9))
                        .cornerRadius(4)
                }
                RuleMark(y: .value("Goal", model.weeklyGoal))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    .foregroundStyle(Theme.inkTertiary)
                if let scrubbedWeek {
                    PointMark(x: .value("Week", scrubbedWeek.weekStart, unit: .weekOfYear),
                              y: .value("Workouts", Double(scrubbedWeek.workoutCount)))
                        .symbolSize(0)
                        .annotation(position: .top, spacing: 6,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            ScrubTooltip(
                                title: "Week of \(scrubbedWeek.weekStart.formatted(.dateTime.month().day()))",
                                value: "\(scrubbedWeek.workoutCount) of \(model.weeklyGoal) workouts")
                        }
                }
            }
            .chartYScale(domain: 0...Double(max(model.weeklyGoal + 1,
                                                (buckets.map(\.workoutCount).max() ?? 0) + 1)))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) {
                    AxisValueLabel(format: .dateTime.month().day())
                        .font(.caption2).foregroundStyle(Theme.inkTertiary)
                }
            }
            .chartYAxis {
                AxisMarks(values: [2, 4]) {
                    AxisGridLine().foregroundStyle(Theme.hairline)
                    AxisValueLabel().font(.caption2).foregroundStyle(Theme.inkTertiary)
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { drag in
                                    guard let plotFrame = proxy.plotFrame else { return }
                                    let x = drag.location.x - geo[plotFrame].origin.x
                                    guard let date: Date = proxy.value(atX: x) else { return }
                                    scrubbedWeek = buckets.min {
                                        abs($0.weekStart.timeIntervalSince(date)) < abs($1.weekStart.timeIntervalSince(date))
                                    }
                                }
                                .onEnded { _ in scrubbedWeek = nil })
                }
            }
            .frame(height: 130)
        }
        .padding(14)
        .cardStyle()
    }

    // MARK: - Body weight

    private var bodyWeightCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Body weight").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                if let last = model.bodyWeights.last {
                    Text("\(Format.weight(last.weight)) lbs")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.inkSecondary)
                        .monospacedDigit()
                }
                Spacer()
                Button("+ Log") { showWeightSheet = true }
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.accent)
            }
            if model.bodyWeights.count >= 2 {
                Chart {
                    ForEach(model.bodyWeights, id: \.id) { entry in
                        AreaMark(x: .value("Date", entry.measuredAt),
                                 yStart: .value("Base", weightDomain.lowerBound),
                                 yEnd: .value("Weight", entry.weight))
                            .foregroundStyle(
                                LinearGradient(colors: [Theme.accent.opacity(0.16), Theme.accent.opacity(0.01)],
                                               startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Date", entry.measuredAt), y: .value("Weight", entry.weight))
                            .foregroundStyle(Theme.accent)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }
                    if let scrubbedWeight {
                        RuleMark(x: .value("Date", scrubbedWeight.measuredAt))
                            .foregroundStyle(Theme.inkTertiary.opacity(0.55))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                        PointMark(x: .value("Date", scrubbedWeight.measuredAt),
                                  y: .value("Weight", scrubbedWeight.weight))
                            .foregroundStyle(Theme.accent)
                            .symbolSize(70)
                            .annotation(position: .top, spacing: 8,
                                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                ScrubTooltip(
                                    title: scrubbedWeight.measuredAt.formatted(.dateTime.month().day().year()),
                                    value: "\(Format.weight(scrubbedWeight.weight)) lbs")
                            }
                    }
                }
                .chartYScale(domain: weightDomain)
                .chartPlotStyle { $0.clipped() }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) {
                        AxisValueLabel(format: .dateTime.month().day())
                            .font(.caption2).foregroundStyle(Theme.inkTertiary)
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 3)) {
                        AxisGridLine().foregroundStyle(Theme.hairline)
                        AxisValueLabel().font(.caption2).foregroundStyle(Theme.inkTertiary)
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { drag in
                                        guard let plotFrame = proxy.plotFrame else { return }
                                        let x = drag.location.x - geo[plotFrame].origin.x
                                        guard let date: Date = proxy.value(atX: x) else { return }
                                        scrubbedWeight = model.bodyWeights.min {
                                            abs($0.measuredAt.timeIntervalSince(date)) < abs($1.measuredAt.timeIntervalSince(date))
                                        }
                                    }
                                    .onEnded { _ in scrubbedWeight = nil })
                    }
                }
                .frame(height: 120)
            } else {
                Text("Log your weight to start the trend line. Strength numbers mean more with body weight beside them.")
                    .font(.caption)
                    .foregroundStyle(Theme.inkTertiary)
                    .padding(.vertical, 8)
            }
        }
        .padding(14)
        .cardStyle()
    }

    private var weightDomain: ClosedRange<Double> {
        let values = model.bodyWeights.map(\.weight)
        guard let min = values.min(), let max = values.max() else { return 0...1 }
        let pad = Swift.max((max - min) * 0.2, 2)
        return (min - pad)...(max + pad)
    }

    // MARK: - Account & backup

    private var accountCard: some View {
        VStack(spacing: 0) {
            if sync.status == .signedOut {
                Button {
                    showAuth = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sign in to back up")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                            Text("Your history syncs to the cloud and restores on any new phone.")
                                .font(.caption)
                                .foregroundStyle(Theme.inkTertiary)
                        }
                        Spacer()
                        Image(systemName: "icloud")
                            .font(.title3)
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sync.email ?? "Signed in")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        Text(backupStatusText)
                            .font(.caption)
                            .foregroundStyle(statusIsError ? Theme.ringLow : Theme.inkTertiary)
                    }
                    Spacer()
                    if sync.status == .syncing {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Back up now") { Task { await sync.push() } }
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(Theme.accent)
                    }
                }
                .padding(14)
                Divider().overlay(Theme.hairline).padding(.leading, 14)
                Button {
                    Task { await sync.signOut() }
                } label: {
                    Text("Sign out")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.ringLow)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .cardStyle()
    }

    private var statusIsError: Bool {
        if case .error = sync.status { return true }
        return false
    }

    private var backupStatusText: String {
        if case .error(let message) = sync.status { return message }
        if let last = sync.lastSyncedAt {
            return "Backed up \(last.formatted(.relative(presentation: .named)))"
        }
        return "Not backed up yet"
    }

    // MARK: - Settings

    private var settingsCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Weekly goal").font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                Spacer()
                Menu {
                    ForEach(1...7, id: \.self) { goal in
                        Button("\(goal) workout\(goal == 1 ? "" : "s")") { model.setWeeklyGoal(goal) }
                    }
                } label: {
                    Text("\(model.weeklyGoal) workouts")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(14)
            Divider().overlay(Theme.hairline).padding(.leading, 14)
            Button {
                showImporter = true
            } label: {
                HStack {
                    Text("Import from Strong").font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                    Spacer()
                    Text("CSV").font(.subheadline).foregroundStyle(Theme.inkTertiary)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.inkTertiary)
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Divider().overlay(Theme.hairline).padding(.leading, 14)
            HStack {
                Text("Units").font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                Spacer()
                Text("lbs").font(.subheadline).foregroundStyle(Theme.inkTertiary)
            }
            .padding(14)
        }
        .cardStyle()
    }
}

private struct LogWeightSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let lastWeight: Double?

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                TextField(lastWeight.map { Format.weight($0) } ?? "180", text: $text)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 44, weight: .bold))
                    .multilineTextAlignment(.center)
                    .monospacedDigit()
                    .focused($focused)
                Text("lbs").font(.subheadline).foregroundStyle(Theme.inkSecondary)
                Spacer()
            }
            .padding(.top, 40)
            .appBackground()
            .navigationTitle("Log Body Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let weight = Double(text), weight > 0 {
                            model.logBodyWeight(weight)
                        }
                        dismiss()
                    }
                    .disabled(Double(text) == nil)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.height(240)])
    }
}
