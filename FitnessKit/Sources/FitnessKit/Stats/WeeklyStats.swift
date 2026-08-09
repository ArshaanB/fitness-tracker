import Foundation

/// One calendar week of training, for the Profile tab's frequency view.
public struct WeekBucket: Identifiable, Sendable, Equatable {
    public let weekStart: Date
    public let workoutCount: Int

    public var id: Date { weekStart }

    public init(weekStart: Date, workoutCount: Int) {
        self.weekStart = weekStart
        self.workoutCount = workoutCount
    }
}

/// Training-consistency stats: workouts per week, weekly-goal streaks, and
/// the goal-driven color zones (PRD §5.4). Week boundaries always come from
/// the calendar, never from 7-day arithmetic.
///
/// Weeks start on MONDAY regardless of locale: on a US calendar (Sunday
/// start), a Sunday workout would open a "new week" and orphan Saturday's
/// session — training weeks conventionally run Mon–Sun.
public enum WeeklyStats {
    private static func mondayFirst(_ calendar: Calendar) -> Calendar {
        var calendar = calendar
        calendar.firstWeekday = 2
        return calendar
    }
    /// The trailing `weeks` calendar weeks ending with the week containing `now`,
    /// ascending by `weekStart`. Weeks with zero workouts are included.
    public static func weekBuckets(workoutsAscending: [LoadedWorkout],
                                   weeks: Int,
                                   now: Date = Date(),
                                   calendar: Calendar = .current) -> [WeekBucket] {
        let calendar = mondayFirst(calendar)
        guard weeks > 0, let currentWeekStart = weekStart(of: now, calendar: calendar) else { return [] }
        let counts = workoutCountsByWeekStart(workoutsAscending, calendar: calendar)
        return (0..<weeks).reversed().compactMap { weeksAgo in
            guard let start = weekStart(weeksBefore: weeksAgo, from: currentWeekStart, calendar: calendar)
            else { return nil }
            return WeekBucket(weekStart: start, workoutCount: counts[start] ?? 0)
        }
    }

    /// Consecutive completed weeks (strictly before the current week) with
    /// `workoutCount >= goal`, counting backward from the most recent completed
    /// week. The in-progress current week extends the streak by 1 once it has
    /// hit the goal, but never breaks it.
    public static func currentStreak(workoutsAscending: [LoadedWorkout],
                                     goal: Int,
                                     now: Date = Date(),
                                     calendar: Calendar = .current) -> Int {
        let calendar = mondayFirst(calendar)
        guard goal > 0, let currentWeekStart = weekStart(of: now, calendar: calendar) else { return 0 }
        let counts = workoutCountsByWeekStart(workoutsAscending, calendar: calendar)

        var streak = 0
        var weeksAgo = 1
        while let start = weekStart(weeksBefore: weeksAgo, from: currentWeekStart, calendar: calendar),
              counts[start] ?? 0 >= goal {
            streak += 1
            weeksAgo += 1
        }
        if counts[currentWeekStart] ?? 0 >= goal {
            streak += 1
        }
        return streak
    }

    /// Mean workouts per week over the trailing `weeks` completed weeks.
    /// The in-progress current week is excluded.
    public static func averagePerWeek(workoutsAscending: [LoadedWorkout],
                                      weeks: Int,
                                      now: Date = Date(),
                                      calendar: Calendar = .current) -> Double {
        let calendar = mondayFirst(calendar)
        guard weeks > 0, let currentWeekStart = weekStart(of: now, calendar: calendar) else { return 0 }
        let counts = workoutCountsByWeekStart(workoutsAscending, calendar: calendar)
        let total = (1...weeks).reduce(0) { sum, weeksAgo in
            guard let start = weekStart(weeksBefore: weeksAgo, from: currentWeekStart, calendar: calendar)
            else { return sum }
            return sum + (counts[start] ?? 0)
        }
        return Double(total) / Double(weeks)
    }

    /// How a week's workout count compares to the weekly goal — drives the
    /// frequency view's colors (met = green, close = yellow, far = orange,
    /// missed = red).
    public enum GoalZone: Sendable, Equatable {
        case met, close, far, missed
    }

    public static func goalZone(count: Int, goal: Int) -> GoalZone {
        if count <= 0 { return .missed }
        if count >= goal { return .met }
        return count >= goal - 1 ? .close : .far
    }

    // MARK: - Week boundaries

    private static func weekStart(of date: Date, calendar: Calendar) -> Date? {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start
    }

    private static func weekStart(weeksBefore count: Int, from weekStart: Date, calendar: Calendar) -> Date? {
        calendar.date(byAdding: .weekOfYear, value: -count, to: weekStart)
            .flatMap { self.weekStart(of: $0, calendar: calendar) }
    }

    private static func workoutCountsByWeekStart(_ workouts: [LoadedWorkout],
                                                 calendar: Calendar) -> [Date: Int] {
        var counts: [Date: Int] = [:]
        for workout in workouts {
            guard let start = weekStart(of: workout.startedAt, calendar: calendar) else { continue }
            counts[start, default: 0] += 1
        }
        return counts
    }
}
