import Charts
import FitnessKit
import SwiftUI
import UniformTypeIdentifiers

struct ProfileView: View {
    @Environment(AppModel.self) private var model

    @State private var showImporter = false
    @State private var importMessage: String?
    @State private var showWeightSheet = false

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
                    settingsCard
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 24)
            }
            .appBackground()
            .navigationTitle("Profile")
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
                Text("last 12 weeks").font(.caption).foregroundStyle(Theme.inkTertiary)
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
                    .annotation(position: .topTrailing, alignment: .trailing) {
                        Text("goal")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.inkTertiary)
                    }
            }
            .chartYScale(domain: 0...Double(max(5, model.weeklyGoal + 1)))
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
                Chart(model.bodyWeights, id: \.id) { entry in
                    AreaMark(x: .value("Date", entry.measuredAt), y: .value("Weight", entry.weight))
                        .foregroundStyle(
                            LinearGradient(colors: [Theme.accent.opacity(0.16), Theme.accent.opacity(0.01)],
                                           startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Date", entry.measuredAt), y: .value("Weight", entry.weight))
                        .foregroundStyle(Theme.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                .chartYScale(domain: weightDomain)
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
                .frame(height: 120)
            } else {
                Text("Log your weight to start the trend line — strength numbers mean more with body weight beside them.")
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
        .presentationDetents([.medium])
    }
}
