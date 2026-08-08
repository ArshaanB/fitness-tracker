import Foundation

/// Core strength math: estimated 1RM and the intensity-ring zones built on it.
public enum Strength {
    /// Epley formula. `weight` is total load; for bodyweight-only sets pass nil upstream.
    public static func estimatedOneRepMax(weight: Double, reps: Int) -> Double? {
        guard weight > 0, reps > 0 else { return nil }
        return weight * (1 + Double(reps) / 30)
    }

    public enum RingZone: Equatable, Sendable {
        /// < 70% of best e1RM
        case low
        /// 70–90%
        case mid
        /// 90–100%
        case high
        /// ≥ 100% — new best e1RM
        case personalRecord
    }

    public static func ringZone(e1RM: Double, bestE1RM: Double) -> RingZone {
        guard bestE1RM > 0 else { return .low }
        let ratio = e1RM / bestE1RM
        switch ratio {
        case ..<0.7: return .low
        case ..<0.9: return .mid
        case ..<1.0: return .high
        default: return .personalRecord
        }
    }
}
