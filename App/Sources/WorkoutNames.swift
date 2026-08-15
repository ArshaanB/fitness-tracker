import Foundation

/// Lighthearted names for workouts started without a template — beats a
/// history full of "Workout".
enum WorkoutNames {
    private static let names = [
        "Operation Swole",
        "Pump Fiction",
        "The Iron Errand",
        "Gains o'Clock",
        "Sweat Equity",
        "Dumbbell Diplomacy",
        "The Heavy Meeting",
        "Bench Warrant",
        "Squat Circus",
        "Deadlift Diaries",
        "The Grunt Work",
        "Flex Appeal",
        "Barbell Ballet",
        "The Swole Patrol",
        "Lift Happens",
        "Iron Therapy",
        "Muscle Memory Lane",
        "The Rack Attack",
        "Chalk It Up",
        "Heavy Metal Hour",
        "Set for Life",
        "Plates of Glory",
        "No Curl Left Behind",
        "Rise and Grind",
        "Maximum Effort",
        "Buff Justice",
        "Quadzilla Rising",
        "The Gainsville Express",
        "Temple of Gains",
        "The One-Rep Wonder",
        "Beast Mode: On",
        "Gym Class Hero",
        "Republic of Reps",
        "The Spotter's Tale",
        "Full Send Friday Energy",
        "Cardio? Never Met Her",
        "Twelve Angry Sets",
        "The Great Gainsby",
        "Lord of the Rings (Gymnastic)",
        "A Farewell to Arms Day",
        "Snatched: A Memoir",
        "The Prestige (Third Set)",
        "Grip It and Rip It",
        "Sore Loser",
        "Delayed Onset Masterpiece",
        "The Progressive Overlord",
        "Everything Everywhere All at Max",
        "Fast and the Curious",
        "Romancing the Stone (Plates)",
        "The Whey Forward",
    ]

    static func random() -> String {
        names.randomElement() ?? "Workout"
    }
}
