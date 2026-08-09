import Charts
import FitnessKit
import SwiftUI

struct ExerciseDetailView: View {
    enum Metric: String, CaseIterable, Identifiable {
        case e1rm = "Est. 1RM"
        case volume = "Volume"
        case reps = "Best reps"
        var id: String { rawValue }
    }

    let exercise: ExerciseHistory
    @State private var metric: Metric = .e1rm
    @State private var scrubbed: ChartPoint?

    private var availableMetrics: [Metric] {
        // "Heaviest" was cut: it tracks est. 1RM almost exactly and already
        // lives as a record tile.
        exercise.isRepOnly ? [.reps] : [.e1rm, .volume]
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                recordsGrid
                chartCard

                Text("Sessions".uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkTertiary)
                    .kerning(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.top, 4)

                ForEach(exercise.sessions.reversed()) { session in
                    SessionRow(session: session, bestE1RM: exercise.bestE1RM,
                               bestReps: exercise.bestReps)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 24)
        }
        .appBackground()
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            if exercise.isRepOnly { metric = .reps }
        }
    }

    private var recordsGrid: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if let best = exercise.bestE1RM {
                        (Text("\(Int(best)) ").font(.title.weight(.bold))
                            + Text("lbs").font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.inkSecondary))
                            .foregroundStyle(Theme.ink)
                        Text("Best est. 1RM").font(.caption).foregroundStyle(Theme.inkSecondary)
                    } else if let bestReps = exercise.bestReps {
                        (Text("\(bestReps) ").font(.title.weight(.bold))
                            + Text("reps").font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.inkSecondary))
                            .foregroundStyle(Theme.ink)
                        Text("Best set").font(.caption).foregroundStyle(Theme.inkSecondary)
                    } else {
                        Text("No sets yet")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                }
                Spacer()
                if exercise.bestE1RM != nil || exercise.bestReps != nil {
                    IntensityRing(ratio: 1, size: 44)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()

            HStack(spacing: 10) {
                if exercise.isRepOnly {
                    recordTile("\(exercise.sessionCount)", "Sessions")
                    recordTile(exercise.lastDone.map {
                        $0.formatted(.relative(presentation: .named))
                    } ?? "Never", "Last done")
                } else {
                    recordTile(exercise.heaviestWeight.map { "\(Format.weight($0)) lbs" } ?? "None yet",
                               "Heaviest weight")
                    recordTile(exercise.bestSet.map { "\(Format.weight($0.weight)) × \($0.reps)" } ?? "None yet",
                               "Best set")
                }
            }
        }
    }

    private func recordTile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline).foregroundStyle(Theme.ink).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(Theme.inkSecondary)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    struct ChartPoint: Identifiable, Equatable {
        let id: String
        let date: Date
        let value: Double
    }

    private struct ChartSegment: Identifiable {
        let id: Int
        let points: [ChartPoint]
    }

    private var chartPoints: [ChartPoint] {
        exercise.sessions.compactMap { session in
            let value: Double? = switch metric {
            case .e1rm: session.bestE1RM
            case .volume: session.volume > 0 ? session.volume : nil
            case .reps: session.bestReps.map(Double.init)
            }
            return value.map { ChartPoint(id: session.id, date: session.date, value: $0) }
        }
    }

    /// Breaks the line at training gaps longer than ~6 weeks so the chart
    /// doesn't draw a misleading bridge across months you didn't train.
    private var segments: [ChartSegment] {
        let gap: TimeInterval = 45 * 86400
        var result: [[ChartPoint]] = []
        var current: [ChartPoint] = []
        for point in chartPoints {
            if let last = current.last, point.date.timeIntervalSince(last.date) > gap {
                result.append(current)
                current = []
            }
            current.append(point)
        }
        if !current.isEmpty { result.append(current) }
        return result.enumerated().map { ChartSegment(id: $0.offset, points: $0.element) }
    }

    private func format(_ value: Double) -> String {
        switch metric {
        case .e1rm: "\(Int(value)) lbs"
        case .volume: value >= 10_000 ? String(format: "%.1fk lbs", value / 1000) : "\(Int(value)) lbs"
        case .reps: "\(Int(value)) reps"
        }
    }

    private var xDomain: ClosedRange<Date> {
        let dates = chartPoints.map(\.date)
        guard let first = dates.min(), let last = dates.max() else {
            return Date()...Date()
        }
        // Breathing room so edge points (and their dots) aren't clipped.
        let pad = Swift.max(last.timeIntervalSince(first) * 0.04, 7 * 86400)
        return first.addingTimeInterval(-pad)...last.addingTimeInterval(pad)
    }

    private var yDomain: ClosedRange<Double> {
        let values = chartPoints.map(\.value)
        guard let min = values.min(), let max = values.max() else { return 0...1 }
        let pad = Swift.max((max - min) * 0.15, 5)
        return (min - pad)...(max + pad)
    }

    private var chartCard: some View {
        VStack(spacing: 10) {
            if availableMetrics.count > 1 {
                Picker("Metric", selection: $metric) {
                    ForEach(availableMetrics) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            } else {
                Text("Best reps per session")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Chart {
                ForEach(segments) { segment in
                    ForEach(segment.points) { point in
                        AreaMark(x: .value("Date", point.date),
                                 yStart: .value("Base", yDomain.lowerBound),
                                 yEnd: .value("Value", point.value),
                                 series: .value("Segment", segment.id))
                            .foregroundStyle(
                                LinearGradient(colors: [Theme.accent.opacity(0.16), Theme.accent.opacity(0.01)],
                                               startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Date", point.date),
                                 y: .value("Value", point.value),
                                 series: .value("Segment", segment.id))
                            .foregroundStyle(Theme.accent)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }
                }
                // Sparse history (one session, or isolated sessions between
                // gaps) draws no visible line, so mark the points themselves.
                if chartPoints.count <= 30 {
                    ForEach(chartPoints) { point in
                        PointMark(x: .value("Date", point.date), y: .value("Value", point.value))
                            .foregroundStyle(Theme.accent)
                            .symbolSize(30)
                    }
                }
                if let scrubbed {
                    RuleMark(x: .value("Date", scrubbed.date))
                        .foregroundStyle(Theme.inkTertiary.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                    PointMark(x: .value("Date", scrubbed.date), y: .value("Value", scrubbed.value))
                        .foregroundStyle(Theme.accent)
                        .symbolSize(70)
                        .annotation(position: .top, spacing: 8,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            ScrubTooltip(title: scrubbed.date.formatted(.dateTime.month().day().year()),
                                         value: format(scrubbed.value))
                        }
                }
            }
            .chartXScale(domain: xDomain)
            .chartYScale(domain: yDomain)
            .chartPlotStyle { $0.clipped() }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) {
                    AxisValueLabel().font(.caption2).foregroundStyle(Theme.inkTertiary)
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
                                    scrubbed = chartPoints.min {
                                        abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
                                    }
                                }
                                .onEnded { _ in scrubbed = nil })
                }
            }
            .frame(height: 170)
        }
        .padding(14)
        .cardStyle()
        .onChange(of: metric) { scrubbed = nil }
        #if DEBUG
        .task {
            // Screenshot hook: render the scrub tooltip without a live touch.
            if ProcessInfo.processInfo.environment["SCRUB"] != nil {
                try? await Task.sleep(for: .seconds(1))
                let points = chartPoints
                if points.count > 4 { scrubbed = points[points.count * 2 / 3] }
            }
        }
        #endif
    }
}

/// Dark floating value bubble shown while scrubbing a chart.
struct ScrubTooltip: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.7))
            Text(value)
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.ink, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .shadow(color: Theme.ink.opacity(0.25), radius: 6, y: 3)
    }
}

private struct SessionRow: View {
    let session: ExerciseHistory.Session
    let bestE1RM: Double?
    let bestReps: Int?

    var body: some View {
        HStack(spacing: 12) {
            IntensityRing(ratio: ratio, size: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.date.formatted(.dateTime.weekday(.wide).month().day()))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(session.sets.map(Format.set).joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(Theme.inkTertiary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer()
            if let e1RM = session.bestE1RM {
                Text("\(Int(e1RM)) e1RM")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .monospacedDigit()
            } else if let reps = session.bestReps {
                Text("\(reps) reps")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var ratio: Double? {
        if let sessionBest = session.bestE1RM, let bestE1RM, bestE1RM > 0 {
            return sessionBest / bestE1RM
        }
        // Rep-only movements: the ring scores best reps against the record.
        if let sessionReps = session.bestReps, let bestReps, bestReps > 0 {
            return Double(sessionReps) / Double(bestReps)
        }
        return nil
    }
}
