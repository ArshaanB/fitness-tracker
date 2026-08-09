import Foundation
import Observation
import SwiftUI

/// Pinch-zoom state for a date-axis chart: pinch narrows the visible x-domain
/// around its center, pinching out (or double-tapping) returns to the full
/// range. Panning isn't needed because zoom always stays anchored inside the
/// full domain.
@MainActor
@Observable
final class ChartZoom {
    private(set) var domain: ClosedRange<Date>?
    private var anchor: ClosedRange<Date>?

    var isZooming: Bool { anchor != nil }

    func magnify(_ magnification: CGFloat, within full: ClosedRange<Date>) {
        let base = anchor ?? domain ?? full
        if anchor == nil { anchor = base }

        let fullSpan = full.upperBound.timeIntervalSince(full.lowerBound)
        let baseSpan = base.upperBound.timeIntervalSince(base.lowerBound)
        var span = baseSpan / max(Double(magnification), 0.05)
        span = min(span, fullSpan)
        span = max(span, 3 * 86400)

        let center = base.lowerBound.addingTimeInterval(baseSpan / 2)
        var lo = center.addingTimeInterval(-span / 2)
        var hi = center.addingTimeInterval(span / 2)
        if lo < full.lowerBound {
            hi = hi.addingTimeInterval(full.lowerBound.timeIntervalSince(lo))
            lo = full.lowerBound
        }
        if hi > full.upperBound {
            lo = max(full.lowerBound, lo.addingTimeInterval(full.upperBound.timeIntervalSince(hi)))
            hi = full.upperBound
        }
        domain = span >= fullSpan ? nil : lo...hi
    }

    func endGesture() {
        anchor = nil
    }

    func reset() {
        anchor = nil
        domain = nil
    }

    /// Programmatic starting window (e.g. "open focused on the last month");
    /// pinching out from here widens toward the full domain as usual.
    func setDomain(_ newDomain: ClosedRange<Date>, within full: ClosedRange<Date>) {
        let lo = max(newDomain.lowerBound, full.lowerBound)
        let hi = min(newDomain.upperBound, full.upperBound)
        guard lo < hi else { return }
        domain = (lo...hi) == full ? nil : lo...hi
    }
}
