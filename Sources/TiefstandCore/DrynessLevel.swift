import Foundation

/// A qualitative band for a `DrynessIndex` value, used to drive the
/// menu-bar color and label.
///
/// **Calibrated against the record, not split at the quarters.**
///
/// The first release cut 0–100 into four equal bands at 25/50/75. That looked
/// tidy and was wrong: the national index is a mean of severity classes across
/// hundreds of gauges, and means over a skewed distribution do not use their
/// upper range. Reconstructed from NIWIS daily records for 2000–2026 — the
/// per-station values together with the class boundaries the portal returns
/// alongside them — the index peaked at **64**, in August 2022. It never
/// reached 75 in twenty-seven years. "Severe" was not rare; it was impossible,
/// and the driest days in a generation were reported as "High" with an empty
/// band above them.
///
/// The thresholds below are the 75th, 90th and 98th percentiles of that
/// reconstruction, checked against a criterion anyone can argue with: the
/// droughts people remember must register, ordinary years must not. They put
/// 2018 (peak 60), 2022 (64), 2025 (52) and 2026 (59) into `severe`, and leave
/// wet years like 2013 (10) and 2024 (11) in `normal`.
///
/// Method and caveats: `docs/superpowers/specs/2026-08-15-band-calibration.md`.
public enum DrynessLevel: String, CaseIterable, Equatable {
    case normal
    case elevated
    case high
    case severe

    /// 75th percentile of the 2000–2026 reconstruction.
    public static let elevatedThreshold = 27.0
    /// 90th percentile.
    public static let highThreshold = 38.0
    /// 98th percentile. Below the observed maximum of 64 on purpose — a top
    /// band that cannot be reached is not a band.
    public static let severeThreshold = 52.0

    public init(index: Double) {
        switch index {
        case ..<DrynessLevel.elevatedThreshold: self = .normal
        case ..<DrynessLevel.highThreshold:     self = .elevated
        case ..<DrynessLevel.severeThreshold:   self = .high
        default:                                self = .severe
        }
    }

    public var label: String {
        switch self {
        case .normal:   return "Normal"
        case .elevated: return "Elevated"
        case .high:     return "High"
        case .severe:   return "Severe"
        }
    }
}

public extension DrynessLevel {

    /// Highest value the reconstructed national index reached in 2000–2026
    /// (August 2022). See the band-calibration spec.
    static let observedMaximum = 64.0

    /// Maps an index onto `0…1` for the colour ramp.
    ///
    /// Not `index / 100`. The index is a mean of severity classes across
    /// hundreds of gauges and does not use its upper range — 64 is the highest
    /// it reached in twenty-seven years — so a linear map spends its top third
    /// on values that never occur and leaves the driest day on record looking
    /// amber.
    ///
    /// Instead the ramp is anchored at the band edges, so colour and label
    /// change together by construction: cool through `normal`, yellow across
    /// `elevated`, orange through `high`, red from `severe` on. Anything above
    /// the observed maximum saturates — "worse than anything on record" is
    /// legitimately the reddest the scale goes.
    ///
    /// The consequence is deliberate: equal steps in the index do **not** give
    /// equal steps in colour. A move from 10 to 20 is weather; from 50 to 60 is
    /// a national event, and the ramp says so.
    static func severityFraction(for index: Double) -> Double {
        let anchors: [(index: Double, fraction: Double)] = [
            (0, 0.0),
            (elevatedThreshold, 0.33),
            (highThreshold, 0.60),
            (severeThreshold, 0.85),
            (observedMaximum, 1.0),
        ]
        guard index > 0 else { return 0 }
        guard index < observedMaximum else { return 1 }

        for (low, high) in zip(anchors, anchors.dropFirst()) where index <= high.index {
            let span = high.index - low.index
            guard span > 0 else { return low.fraction }
            return low.fraction + (high.fraction - low.fraction) * (index - low.index) / span
        }
        return 1
    }
}
