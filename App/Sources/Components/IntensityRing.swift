import SwiftUI

/// The app's signature element: a donut showing how a set (or session) compares
/// to the exercise's best estimated 1RM. Rainbow at >= 100%.
struct IntensityRing: View {
    /// e1RM ÷ best e1RM. Nil renders an empty track.
    let ratio: Double?
    var size: CGFloat = 26

    private var lineWidth: CGFloat { size * 0.19 }

    var body: some View {
        ZStack {
            Circle().stroke(Theme.ringTrack, lineWidth: lineWidth)
            if let ratio {
                if ratio >= 1 {
                    Circle().stroke(
                        AngularGradient(colors: Theme.rainbow, center: .center),
                        lineWidth: lineWidth)
                } else {
                    Circle()
                        .trim(from: 0, to: max(0.06, ratio))
                        .stroke(color(for: ratio),
                                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(accessibilityDescription)
    }

    /// Rings encode intensity purely in color; VoiceOver gets it in words.
    private var accessibilityDescription: String {
        guard let ratio else { return "No intensity data" }
        let percent = Int((ratio * 100).rounded())
        switch ratio {
        case ..<0.7: return "Intensity \(percent) percent of record, far from max"
        case ..<0.9: return "Intensity \(percent) percent of record, working weight"
        case ..<1.0: return "Intensity \(percent) percent of record, near your record"
        default: return "New record intensity, \(percent) percent of previous best"
        }
    }

    private func color(for ratio: Double) -> Color {
        switch ratio {
        case ..<0.7: Theme.ringLow
        case ..<0.9: Theme.ringMid
        default: Theme.ringHigh
        }
    }
}
