import Charts
import FitnessKit
import SwiftUI

struct ExerciseDetailView: View {
    enum Metric: String, CaseIterable, Identifiable {
        case e1rm = "Est. 1RM"
        case heaviest = "Heaviest"
        case volume = "Volume"
        var id: String { rawValue }
    }

    let exercise: ExerciseHistory
    @State private var metric: Metric = .e1rm

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
                    SessionRow(session: session, bestE1RM: exercise.bestE1RM)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 24)
        }
        .appBackground()
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.large)
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
                    } else {
                        Text("—").font(.title.weight(.bold)).foregroundStyle(Theme.inkSecondary)
                    }
                    Text("Best est. 1RM").font(.caption).foregroundStyle(Theme.inkSecondary)
                }
                Spacer()
                IntensityRing(ratio: 1, size: 44)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()

            HStack(spacing: 10) {
                recordTile(exercise.heaviestWeight.map { "\(Format.weight($0)) lbs" } ?? "—",
                           "Heaviest weight")
                recordTile(exercise.bestSet.map { "\(Format.weight($0.weight)) × \($0.reps)" } ?? "—",
                           "Best set")
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

    private struct ChartPoint: Identifiable {
        let id: String
        let date: Date
        let value: Double
    }

    private var chartPoints: [ChartPoint] {
        exercise.sessions.compactMap { session in
            let value: Double? = switch metric {
            case .e1rm: session.bestE1RM
            case .heaviest: session.heaviest
            case .volume: session.volume > 0 ? session.volume : nil
            }
            return value.map { ChartPoint(id: session.id, date: session.date, value: $0) }
        }
    }

    private var chartCard: some View {
        VStack(spacing: 10) {
            Picker("Metric", selection: $metric) {
                ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            Chart(chartPoints) { point in
                AreaMark(x: .value("Date", point.date), y: .value("Value", point.value))
                    .foregroundStyle(
                        LinearGradient(colors: [Theme.accent.opacity(0.16), Theme.accent.opacity(0.01)],
                                       startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Date", point.date), y: .value("Value", point.value))
                    .foregroundStyle(Theme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) {
                    AxisValueLabel().font(.caption2).foregroundStyle(Theme.inkTertiary)
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) {
                    AxisGridLine().foregroundStyle(Theme.hairline)
                    AxisValueLabel().font(.caption2).foregroundStyle(Theme.inkTertiary)
                }
            }
            .frame(height: 170)
        }
        .padding(14)
        .cardStyle()
    }
}

private struct SessionRow: View {
    let session: ExerciseHistory.Session
    let bestE1RM: Double?

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
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var ratio: Double? {
        guard let sessionBest = session.bestE1RM, let bestE1RM, bestE1RM > 0 else { return nil }
        return sessionBest / bestE1RM
    }
}
