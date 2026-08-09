import Charts
import FitnessKit
import SwiftUI

/// The exercise progress chart with metric switching, scrubbing, and pinch
/// zoom. A self-contained view on purpose: scrub/zoom state lives HERE, so a
/// finger dragging across the chart re-renders only this card instead of the
/// whole detail screen (nav bar, records, and a hundred session rows).
struct ExerciseChartCard: View {
    enum Metric: String, CaseIterable, Identifiable {
        case e1rm = "Est. 1RM"
        case volume = "Volume"
        case reps = "Best reps"
        var id: String { rawValue }
    }

    let exercise: ExerciseHistory

    @State private var metric: Metric = .e1rm
    @State private var scrubbed: ChartPoint?
    @State private var crosshair: CrosshairPosition?
    @State private var zoom = ChartZoom()

    /// Pixel-space crosshair location, captured once in the gesture handler.
    /// The overlay renders from these plain floats and never queries the chart
    /// proxy during render — deriving positions from chart internals at render
    /// time makes Charts dirty its own layout every frame (100% CPU loop).
    struct CrosshairPosition: Equatable {
        var x: CGFloat
        var y: CGFloat
        var top: CGFloat
        var bottom: CGFloat
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

    private var availableMetrics: [Metric] {
        // "Heaviest" was cut: it tracks est. 1RM almost exactly and already
        // lives as a record tile.
        exercise.isRepOnly ? [.reps] : [.e1rm, .volume]
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

    private var visibleXDomain: ClosedRange<Date> { zoom.domain ?? xDomain }

    private var visiblePoints: [ChartPoint] {
        let visible = chartPoints.filter { visibleXDomain.contains($0.date) }
        return visible.isEmpty ? chartPoints : visible
    }

    private var yDomain: ClosedRange<Double> {
        let values = visiblePoints.map(\.value)
        guard let min = values.min(), let max = values.max() else { return 0...1 }
        let pad = Swift.max((max - min) * 0.15, 5)
        return (min - pad)...(max + pad)
    }

    var body: some View {
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
                // Zooming in far enough always reveals individual sessions.
                if visiblePoints.count <= 30 {
                    ForEach(visiblePoints) { point in
                        PointMark(x: .value("Date", point.date), y: .value("Value", point.value))
                            .foregroundStyle(Theme.accent)
                            .symbolSize(30)
                    }
                }
            }
            .chartXScale(domain: visibleXDomain)
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
                                    guard !zoom.isZooming,
                                          let plotFrame = proxy.plotFrame else { return }
                                    let plot = geo[plotFrame]
                                    let x = drag.location.x - plot.origin.x
                                    guard let date: Date = proxy.value(atX: x) else { return }
                                    guard let nearest = visiblePoints.min(by: {
                                        abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
                                    }) else { return }
                                    scrubbed = nearest
                                    if let px = proxy.position(forX: nearest.date),
                                       let py = proxy.position(forY: nearest.value) {
                                        crosshair = CrosshairPosition(x: plot.minX + px,
                                                                      y: plot.minY + py,
                                                                      top: plot.minY,
                                                                      bottom: plot.maxY)
                                    }
                                }
                                .onEnded { _ in
                                    scrubbed = nil
                                    crosshair = nil
                                })
                        .simultaneousGesture(
                            MagnifyGesture()
                                .onChanged { value in
                                    scrubbed = nil
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
            // Chart annotations clip (or worse) near plot edges; a readout
            // pinned above the chart never does.
            .overlay(alignment: .top) {
                if let scrubbed {
                    ScrubTooltip(title: scrubbed.date.formatted(.dateTime.month().day().year()),
                                 value: format(scrubbed.value))
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 170)
        }
        .padding(14)
        .cardStyle()
        .onChange(of: metric) {
            scrubbed = nil
            zoom.reset()
        }
        .onAppear {
            if exercise.isRepOnly { metric = .reps }
        }
        #if DEBUG
        .task {
            // Screenshot hook: render the scrub tooltip without a live touch.
            // Sleeps must PROPAGATE cancellation (no try?): a cancelled sleep
            // that falls through to a state write makes every task restart
            // re-invalidate the view, which is a 100%-CPU loop.
            if let mode = ProcessInfo.processInfo.environment["SCRUB"] {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                let points = chartPoints
                guard !points.isEmpty else { return }
                scrubbed = mode == "edge" ? points.last : points[points.count * 2 / 3]
                do { try await Task.sleep(for: .seconds(8)) } catch { return }
                scrubbed = nil
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
