import Foundation

/// Which of the three recorded 0–100 scores a curve plots.
///
/// All three share one scale by construction — the index is the mean of the
/// other two — so they can be drawn on a single set of axes. That comparison
/// is the point: the headline number averages the two compartments together
/// and therefore hides which one is driving it.
public enum DrynessMetric: String, CaseIterable, Sendable {
    case index
    case discharge
    case groundwater

    public var label: String {
        switch self {
        case .index:       return "Index"
        case .discharge:   return "Discharge"
        case .groundwater: return "Groundwater"
        }
    }
}

public extension Array where Element == DrynessSample {

    /// Plottable points for one metric.
    ///
    /// A sample with no score for that domain is **skipped**, not zeroed:
    /// `DrynessIndex.combined` deliberately still produces an index when one
    /// domain is unavailable, recording `nil` for the missing one. Plotting
    /// that as 0 would draw a dive to "no drought at all" where the truth is
    /// "we didn't hear from this domain". A skip becomes a gap, which is what
    /// it is.
    func points(for metric: DrynessMetric) -> [TrendPoint] {
        compactMap { sample in
            let value: Double?
            switch metric {
            case .index:       value = sample.index
            case .discharge:   value = sample.dischargeScore
            case .groundwater: value = sample.groundwaterScore
            }
            return value.map { TrendPoint(date: sample.timestamp, value: $0) }
        }
    }
}
