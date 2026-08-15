import FitnessKit
import SwiftUI

enum Theme {
    static let accent = Color(red: 10 / 255, green: 92 / 255, blue: 255 / 255)
    static let ink = Color(red: 14 / 255, green: 23 / 255, blue: 38 / 255)
    static let inkSecondary = Color(red: 107 / 255, green: 118 / 255, blue: 136 / 255)
    static let inkTertiary = Color(red: 152 / 255, green: 161 / 255, blue: 175 / 255)
    static let ringLow = Color(red: 255 / 255, green: 69 / 255, blue: 58 / 255)
    static let ringMid = Color(red: 255 / 255, green: 176 / 255, blue: 32 / 255)
    static let ringHigh = Color(red: 45 / 255, green: 190 / 255, blue: 95 / 255)
    static let ringTrack = Color(red: 233 / 255, green: 236 / 255, blue: 241 / 255)
    static let groundTop = Color(red: 235 / 255, green: 241 / 255, blue: 249 / 255)
    static let groundBottom = Color(red: 245 / 255, green: 247 / 255, blue: 251 / 255)
    static let card = Color.white
    static let hairline = Color(red: 239 / 255, green: 242 / 255, blue: 247 / 255)

    static let rainbow: [Color] = [
        ringLow, ringMid, Color(red: 247 / 255, green: 231 / 255, blue: 51 / 255),
        ringHigh, Color(red: 56 / 255, green: 199 / 255, blue: 216 / 255),
        accent, Color(red: 157 / 255, green: 92 / 255, blue: 255 / 255), ringLow,
    ]
}

struct AppBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.background(
            LinearGradient(colors: [Theme.groundTop, Theme.groundBottom],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea())
    }
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color(red: 16 / 255, green: 38 / 255, blue: 74 / 255).opacity(0.07),
                    radius: 11, y: 4)
    }
}

extension View {
    func appBackground() -> some View { modifier(AppBackground()) }
    func cardStyle() -> some View { modifier(CardStyle()) }
}

/// Display unit for weights. Storage is ALWAYS pounds; conversion happens at
/// the display/entry boundary only, so records, rings, and 8 years of history
/// stay consistent whichever unit is shown.
enum WeightUnit: String {
    case lbs
    case kg

    var label: String { rawValue }

    /// Stored pounds → display value.
    func display(_ storedLbs: Double) -> Double {
        self == .kg ? storedLbs * 0.45359237 : storedLbs
    }

    /// Entered display value → stored pounds.
    func toStorage(_ displayValue: Double) -> Double {
        self == .kg ? displayValue / 0.45359237 : displayValue
    }
}

@MainActor
enum Format {
    /// Set by AppModel when settings load or change; every weight the user
    /// sees flows through this.
    static var unit: WeightUnit = .lbs

    static var unitLabel: String { unit.label }

    static func duration(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func volume(_ storedLbs: Double) -> String {
        Int(unit.display(storedLbs).rounded()).formatted(.number.grouping(.automatic))
    }

    /// Converted display number, trimmed: "185", or "83.9" in kg.
    static func weight(_ storedLbs: Double) -> String {
        let value = (unit.display(storedLbs) * 10).rounded() / 10
        return value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(value)
    }

    /// Whole-number converted weight for stat-style values (e1RM).
    static func wholeWeight(_ storedLbs: Double) -> String {
        String(Int(unit.display(storedLbs).rounded()))
    }

    static func set(_ set: LoadedSet) -> String {
        if let w = set.weight, let r = set.reps { return "\(weight(w))×\(r)" }
        if let r = set.reps { return "BW×\(r)" }
        if let s = set.seconds { return "\(Int(s))s" }
        return ""
    }
}
