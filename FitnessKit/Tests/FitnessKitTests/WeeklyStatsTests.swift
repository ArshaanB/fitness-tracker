import Foundation
import Testing
@testable import FitnessKit

/// Fixed calendar so week boundaries are deterministic regardless of the
/// machine running the tests: gregorian, UTC, Sunday-start weeks.
private let utcCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

/// Noon UTC on the given day.
private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
    utcCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
}

private func workout(on date: Date, id: String = UUID().uuidString) -> LoadedWorkout {
    LoadedWorkout(id: id, name: "Workout", startedAt: date, finishedAt: nil, exercises: [])
}

private func startOfWeek(containing date: Date) -> Date {
    utcCalendar.dateInterval(of: .weekOfYear, for: date)!.start
}

/// Saturday — near the end of its week, so the "current week" is in progress.
private let now = day(2026, 8, 8)

@Suite struct WeekBucketTests {
    @Test func bucketsIncludeGapWeeksAndAscend() {
        // Weeks (ascending): now-3w has 2 workouts, now-2w has none,
        // now-1w has 1, current week has 1.
        let workouts = [
            workout(on: day(2026, 7, 13)),
            workout(on: day(2026, 7, 15)),
            workout(on: day(2026, 7, 28)),
            workout(on: day(2026, 8, 3)),
        ]
        let buckets = WeeklyStats.weekBuckets(
            workoutsAscending: workouts, weeks: 4, now: now, calendar: utcCalendar)

        let counts = buckets.map(\.workoutCount)
        #expect(counts == [2, 0, 1, 1])

        let expectedStarts = [
            startOfWeek(containing: day(2026, 7, 13)),
            startOfWeek(containing: day(2026, 7, 20)),
            startOfWeek(containing: day(2026, 7, 28)),
            startOfWeek(containing: now),
        ]
        let starts = buckets.map(\.weekStart)
        #expect(starts == expectedStarts)
        #expect(buckets.map(\.id) == expectedStarts)
    }

    @Test func emptyForNonPositiveWeeks() {
        let buckets = WeeklyStats.weekBuckets(
            workoutsAscending: [workout(on: now)], weeks: 0, now: now, calendar: utcCalendar)
        #expect(buckets.isEmpty)
    }
}

@Suite struct CurrentStreakTests {
    @Test func streakStopsAtBelowGoalWeek() {
        // now-3w: 1 workout (below goal 2) breaks the run; now-2w and now-1w meet it.
        let workouts = [
            workout(on: day(2026, 7, 15)),
            workout(on: day(2026, 7, 20)),
            workout(on: day(2026, 7, 22)),
            workout(on: day(2026, 7, 27)),
            workout(on: day(2026, 7, 29)),
        ]
        let streak = WeeklyStats.currentStreak(
            workoutsAscending: workouts, goal: 2, now: now, calendar: utcCalendar)
        #expect(streak == 2)
    }

    @Test func inProgressWeekDoesNotBreakStreak() {
        // Two completed weeks at goal; current week has only 1 of 2 so far.
        let workouts = [
            workout(on: day(2026, 7, 20)),
            workout(on: day(2026, 7, 22)),
            workout(on: day(2026, 7, 27)),
            workout(on: day(2026, 7, 29)),
            workout(on: day(2026, 8, 3)),
        ]
        let streak = WeeklyStats.currentStreak(
            workoutsAscending: workouts, goal: 2, now: now, calendar: utcCalendar)
        #expect(streak == 2)
    }

    @Test func inProgressWeekExtendsStreakOnceGoalHit() {
        // Same two completed weeks, but the current week already hit the goal.
        let workouts = [
            workout(on: day(2026, 7, 20)),
            workout(on: day(2026, 7, 22)),
            workout(on: day(2026, 7, 27)),
            workout(on: day(2026, 7, 29)),
            workout(on: day(2026, 8, 3)),
            workout(on: day(2026, 8, 5)),
        ]
        let streak = WeeklyStats.currentStreak(
            workoutsAscending: workouts, goal: 2, now: now, calendar: utcCalendar)
        #expect(streak == 3)
    }

    @Test func zeroWhenLastCompletedWeekMissedGoal() {
        // Only the current week has workouts; last completed week is empty.
        let workouts = [
            workout(on: day(2026, 8, 3)),
            workout(on: day(2026, 8, 5)),
        ]
        let streak = WeeklyStats.currentStreak(
            workoutsAscending: workouts, goal: 2, now: now, calendar: utcCalendar)
        #expect(streak == 1)

        let harderGoal = WeeklyStats.currentStreak(
            workoutsAscending: workouts, goal: 3, now: now, calendar: utcCalendar)
        #expect(harderGoal == 0)
    }
}

@Suite struct AveragePerWeekTests {
    @Test func averageExcludesInProgressWeek() {
        // Completed weeks (ascending): 3, 1, 2 workouts. Current week has 2
        // that must not count.
        let workouts = [
            workout(on: day(2026, 7, 13)),
            workout(on: day(2026, 7, 15)),
            workout(on: day(2026, 7, 17)),
            workout(on: day(2026, 7, 22)),
            workout(on: day(2026, 7, 27)),
            workout(on: day(2026, 7, 29)),
            workout(on: day(2026, 8, 3)),
            workout(on: day(2026, 8, 5)),
        ]
        let average = WeeklyStats.averagePerWeek(
            workoutsAscending: workouts, weeks: 3, now: now, calendar: utcCalendar)
        let expected = 6.0 / 3.0
        #expect(average == expected)
    }

    @Test func emptyWeeksDragTheAverageDown() {
        let workouts = [workout(on: day(2026, 7, 29))]
        let average = WeeklyStats.averagePerWeek(
            workoutsAscending: workouts, weeks: 4, now: now, calendar: utcCalendar)
        let expected = 1.0 / 4.0
        #expect(average == expected)
    }
}

@Suite struct GoalZoneTests {
    @Test func defaultGoalOfThree() {
        #expect(WeeklyStats.goalZone(count: 4, goal: 3) == .met)
        #expect(WeeklyStats.goalZone(count: 3, goal: 3) == .met)
        #expect(WeeklyStats.goalZone(count: 2, goal: 3) == .close)
        #expect(WeeklyStats.goalZone(count: 1, goal: 3) == .far)
        #expect(WeeklyStats.goalZone(count: 0, goal: 3) == .missed)
    }

    @Test func generalizesToOtherGoals() {
        #expect(WeeklyStats.goalZone(count: 1, goal: 1) == .met)
        #expect(WeeklyStats.goalZone(count: 0, goal: 1) == .missed)
        #expect(WeeklyStats.goalZone(count: 5, goal: 5) == .met)
        #expect(WeeklyStats.goalZone(count: 4, goal: 5) == .close)
        #expect(WeeklyStats.goalZone(count: 3, goal: 5) == .far)
        #expect(WeeklyStats.goalZone(count: 0, goal: 5) == .missed)
    }
}
