import FitnessKit
import SwiftUI

struct ExerciseDetailView: View {
    let exercise: ExerciseHistory

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                recordsGrid
                ExerciseChartCard(exercise: exercise)

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
    }

    private var recordsGrid: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if let best = exercise.bestE1RM {
                        (Text("\(Format.wholeWeight(best)) ").font(.title.weight(.bold))
                            + Text(Format.unitLabel).font(.subheadline.weight(.semibold))
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
                    recordTile(exercise.heaviestWeight.map { "\(Format.weight($0)) \(Format.unitLabel)" } ?? "None yet",
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
                Text("\(Format.wholeWeight(e1RM)) e1RM")
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
