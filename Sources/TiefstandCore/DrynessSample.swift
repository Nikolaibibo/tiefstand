import Foundation

/// One recorded observation of the national Dryness Index.
///
/// Both domain scores are stored even though only the combined index is
/// plotted today, so per-domain curves can be added later without a hole in
/// the record. Samples are the *only* source of index history — NIWIS serves
/// the current aggregate and nothing else, so whatever isn't recorded here is
/// gone for good.
public struct DrynessSample: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let index: Double
    public let dischargeScore: Double?
    public let groundwaterScore: Double?

    /// Timestamps are normalised to whole seconds.
    ///
    /// The log is stored as readable ISO-8601, which carries no sub-second
    /// component, and samples are two hours apart anyway. Rounding here makes
    /// `append` → `load` an exact round-trip instead of a near-miss that only
    /// ever surfaces as a baffling equality failure.
    public init(timestamp: Date,
                index: Double,
                dischargeScore: Double?,
                groundwaterScore: Double?) {
        self.timestamp = Date(timeIntervalSince1970:
            timestamp.timeIntervalSince1970.rounded(.down))
        self.index = index
        self.dischargeScore = dischargeScore
        self.groundwaterScore = groundwaterScore
    }

    /// Snapshots a freshly computed index.
    public init(index: DrynessIndex, timestamp: Date) {
        self.init(timestamp: timestamp,
                  index: index.value,
                  dischargeScore: index.dischargeScore,
                  groundwaterScore: index.groundwaterScore)
    }
}
