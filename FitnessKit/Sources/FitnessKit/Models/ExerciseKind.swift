import Foundation

public enum ExerciseKind: String, Codable, Sendable, CaseIterable {
    case barbell
    case dumbbell
    case machine
    case bodyweight

    /// Infers equipment from Strong's naming convention, e.g. "Bench Press (Barbell)",
    /// "Triceps Extension (Cable)", "Pull Up".
    public static func infer(fromStrongName name: String) -> ExerciseKind {
        if name.contains("(Barbell)") || name.contains("(Smith Machine)") { return .barbell }
        if name.contains("(Dumbbell)") { return .dumbbell }
        if name.contains("(Cable)") || name.contains("(Machine") || name.contains("(Band)")
            || name.contains("(Treadmill)") || name.contains("(Plate Loaded)") {
            return .machine
        }
        return .bodyweight
    }
}
