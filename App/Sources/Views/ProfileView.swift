import Charts
import FitnessKit
import SwiftUI
import UniformTypeIdentifiers

struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @Environment(SyncModel.self) private var sync

    /// Cloud backup is built but not launch-ready; hidden until the sync flow
    /// gets its polish pass.
    private let backupEnabled = false

    @State private var showAuth = false
    @State private var showImporter = false
    @State private var importMessage: String?
    @State private var showWeightSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if !model.isReady {
                    ProgressView("Importing history…")
                        .padding(.top, 120)
                } else {
                    LazyVStack(spacing: 12) {
                        tiles
                        FrequencyChartCard(buckets: model.weekBuckets, goal: model.weeklyGoal)
                        bodyWeightCard
                        if backupEnabled {
                            accountCard
                        }
                        settingsCard
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 24)
                }
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
            let thisWeek = model.weekBuckets.last?.workoutCount ?? 0
            tile("\(thisWeek)", "This week",
                 color: FrequencyChartCard.goalColor(thisWeek, goal: model.weeklyGoal))
            tile("\(model.currentStreak) wks", "Streak at goal", color: Theme.ink)
            tile(String(format: "%.1f", model.weeklyAverage), "Avg / week", color: Theme.ink)
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
                BodyWeightChart(weights: model.bodyWeights)
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
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Import from Strong").font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                        Text("Only the CSV from Strong's \"Export workouts\" works here. Exports from other apps use different formats.")
                            .font(.caption)
                            .foregroundStyle(Theme.inkTertiary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.inkTertiary)
                        .padding(.top, 4)
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

// MARK: - Frequency chart (self-contained: scrub state stays local)

struct FrequencyChartCard: View {
    let buckets: [WeekBucket]
    let goal: Int

    @State private var scrubbedWeek: WeekBucket?

    /// While scrubbing, the touched bar stays vivid and every other bar fades,
    /// so it's unmistakable which week the readout describes.
    private func barOpacity(bucket: WeekBucket, isCurrentWeek: Bool) -> Double {
        if let scrubbedWeek {
            return bucket.id == scrubbedWeek.id ? 1.0 : 0.25
        }
        return isCurrentWeek ? 0.45 : 0.9
    }

    static func goalColor(_ count: Int, goal: Int) -> Color {
        switch WeeklyStats.goalZone(count: count, goal: goal) {
        case .met: Theme.ringHigh
        case .close: Color(red: 1, green: 192 / 255, blue: 46 / 255)
        case .far: Color(red: 242 / 255, green: 140 / 255, blue: 13 / 255)
        case .missed: Theme.ringLow
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Workouts per week").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                Spacer()
                Text("goal \(goal)/wk · last 12 weeks")
                    .font(.caption)
                    .foregroundStyle(Theme.inkTertiary)
                    .monospacedDigit()
            }
            Chart {
                ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
                    BarMark(x: .value("Week", bucket.weekStart, unit: .weekOfYear),
                            y: .value("Workouts", max(Double(bucket.workoutCount), 0.12)),
                            width: .ratio(0.55))
                        .foregroundStyle(Self.goalColor(bucket.workoutCount, goal: goal)
                            .opacity(barOpacity(bucket: bucket, isCurrentWeek: index == buckets.count - 1)))
                        .cornerRadius(4)
                }
                RuleMark(y: .value("Goal", goal))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    .foregroundStyle(Theme.inkTertiary)
            }
            .overlay(alignment: .top) {
                if let scrubbedWeek {
                    ScrubTooltip(
                        title: "Week of \(scrubbedWeek.weekStart.formatted(.dateTime.month().day()))",
                        value: "\(scrubbedWeek.workoutCount) of \(goal) workouts")
                }
            }
            .chartYScale(domain: 0...Double(max(goal + 1,
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
                                    // Snap to the bucket CONTAINING the touch
                                    // date; nearest-weekStart picks the wrong
                                    // week for the latter half of each bar.
                                    scrubbedWeek = buckets.last { $0.weekStart <= date } ?? buckets.first
                                }
                                .onEnded { _ in scrubbedWeek = nil })
                }
            }
            .frame(height: 130)
        }
        .padding(14)
        .cardStyle()
    }
}

// MARK: - Body weight chart (self-contained: scrub/zoom state stays local)

struct BodyWeightChart: View {
    let weights: [BodyWeightRecord]

    @State private var scrubbedWeight: BodyWeightRecord?
    @State private var crosshair: ExerciseChartCard.CrosshairPosition?
    @State private var zoom = ChartZoom()

    private var xDomain: ClosedRange<Date> {
        let dates = weights.map(\.measuredAt)
        guard let first = dates.min(), let last = dates.max() else { return Date()...Date() }
        let pad = Swift.max(last.timeIntervalSince(first) * 0.04, 86400)
        return first.addingTimeInterval(-pad)...last.addingTimeInterval(pad)
    }

    private func visibleWeights(in domain: ClosedRange<Date>?) -> [BodyWeightRecord] {
        guard let domain else { return weights }
        let visible = weights.filter { domain.contains($0.measuredAt) }
        return visible.isEmpty ? weights : visible
    }

    private func yDomain(of visible: [BodyWeightRecord]) -> ClosedRange<Double> {
        let values = visible.map(\.weight)
        guard let min = values.min(), let max = values.max() else { return 0...1 }
        let pad = Swift.max((max - min) * 0.2, 2)
        return (min - pad)...(max + pad)
    }

    var body: some View {
        // Derived once per render (same O(n²)-avoidance as the exercise chart).
        let visibleWeights = visibleWeights(in: zoom.domain)
        let yDomain = yDomain(of: visibleWeights)

        chart(visibleWeights: visibleWeights, yDomain: yDomain)
            .onAppear {
                let full = xDomain
                if full.upperBound.timeIntervalSince(full.lowerBound) > 60 * 86400,
                   let last = weights.last?.measuredAt {
                    zoom.setDomain(last.addingTimeInterval(-30 * 86400)...last.addingTimeInterval(2 * 86400),
                                   within: full)
                }
            }
    }

    private func chart(visibleWeights: [BodyWeightRecord],
                       yDomain: ClosedRange<Double>) -> some View {
        Chart {
            ForEach(visibleWeights, id: \.id) { entry in
                AreaMark(x: .value("Date", entry.measuredAt),
                         yStart: .value("Base", yDomain.lowerBound),
                         yEnd: .value("Weight", entry.weight))
                    .foregroundStyle(
                        LinearGradient(colors: [Theme.accent.opacity(0.16), Theme.accent.opacity(0.01)],
                                       startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Date", entry.measuredAt), y: .value("Weight", entry.weight))
                    .foregroundStyle(Theme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
        .chartXScale(domain: zoom.domain ?? xDomain)
        .chartYScale(domain: yDomain)
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
                                guard !zoom.isZooming,
                                      let plotFrame = proxy.plotFrame else { return }
                                let plot = geo[plotFrame]
                                let x = drag.location.x - plot.origin.x
                                guard let date: Date = proxy.value(atX: x) else { return }
                                guard let nearest = visibleWeights.min(by: {
                                    abs($0.measuredAt.timeIntervalSince(date)) < abs($1.measuredAt.timeIntervalSince(date))
                                }) else { return }
                                scrubbedWeight = nearest
                                if let px = proxy.position(forX: nearest.measuredAt),
                                   let py = proxy.position(forY: nearest.weight) {
                                    crosshair = .init(x: plot.minX + px, y: plot.minY + py,
                                                      top: plot.minY, bottom: plot.maxY)
                                }
                            }
                            .onEnded { _ in
                                scrubbedWeight = nil
                                crosshair = nil
                            })
                    .simultaneousGesture(
                        MagnifyGesture()
                            .onChanged { value in
                                scrubbedWeight = nil
                                crosshair = nil
                                zoom.magnify(value.magnification, within: xDomain)
                            }
                            .onEnded { _ in zoom.endGesture() })
                    .onTapGesture(count: 2) { zoom.reset() }
            }
        }
        .overlay {
            if let crosshair {
                ZStack(alignment: .topLeading) {
                    Path { path in
                        path.move(to: CGPoint(x: crosshair.x, y: crosshair.top))
                        path.addLine(to: CGPoint(x: crosshair.x, y: crosshair.bottom))
                    }
                    .stroke(Theme.inkTertiary.opacity(0.55), lineWidth: 1)
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        .position(x: crosshair.x, y: crosshair.y)
                }
                .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .top) {
            if let scrubbedWeight {
                ScrubTooltip(
                    title: scrubbedWeight.measuredAt.formatted(.dateTime.month().day().year()),
                    value: "\(Format.weight(scrubbedWeight.weight)) lbs")
                    .allowsHitTesting(false)
            }
        }
        .frame(height: 120)
    }
}

private struct LogWeightSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let lastWeight: Double?

    @State private var text = ""
    @FocusState private var focused: Bool

    private var parsed: Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                TextField(lastWeight.map { Format.weight($0) } ?? "180", text: $text)
                    .keyboardType(.decimalPad)
                    .font(.system(size: 44, weight: .bold))
                    .multilineTextAlignment(.center)
                    .monospacedDigit()
                    .focused($focused)
                Text("lbs").font(.subheadline).foregroundStyle(Theme.inkSecondary)
                if let last = model.bodyWeights.last {
                    Button(role: .destructive) {
                        model.deleteBodyWeight(id: last.id)
                        dismiss()
                    } label: {
                        Text("Delete last entry (\(Format.weight(last.weight)) lbs, \(last.measuredAt.formatted(.dateTime.month().day())))")
                            .font(.footnote.weight(.medium))
                    }
                }
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
                        if let weight = parsed, weight > 0 {
                            model.logBodyWeight(weight)
                        }
                        dismiss()
                    }
                    .disabled(parsed == nil)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.height(280)])
    }
}
