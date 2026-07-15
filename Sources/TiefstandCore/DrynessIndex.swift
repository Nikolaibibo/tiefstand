import Foundation

/// The headline metric: a 0–100 "how dry is Germany right now" score,
/// the 50/50 mean of the discharge (surface water) and groundwater
/// severity scores. Water level is deliberately excluded to avoid
/// double-counting surface water; spring flow is dashboard-only.
public struct DrynessIndex: Equatable {
    public let value: Double
    public let dischargeScore: Double?
    public let groundwaterScore: Double?

    /// Averages only the domains that currently have classified data.
    /// Returns `nil` when neither domain has any classified station.
    public static func combined(discharge: DomainAggregate,
                                groundwater: DomainAggregate) -> DrynessIndex? {
        let d = discharge.severityScore
        let g = groundwater.severityScore
        let scores = [d, g].compactMap { $0 }
        guard !scores.isEmpty else { return nil }
        let value = scores.reduce(0, +) / Double(scores.count)
        return DrynessIndex(value: value, dischargeScore: d, groundwaterScore: g)
    }
}
