import Foundation

/// A NIWIS national aggregate for one water domain: how many measuring
/// stations fall into each low-water class right now.
public struct DomainAggregate: Equatable, Decodable {
    public let keinNiedrigwasser: Int
    public let niedrig: Int
    public let sehrNiedrig: Int
    public let extremNiedrig: Int
    public let keineDaten: Int

    public init(keinNiedrigwasser: Int, niedrig: Int, sehrNiedrig: Int,
                extremNiedrig: Int, keineDaten: Int) {
        self.keinNiedrigwasser = keinNiedrigwasser
        self.niedrig = niedrig
        self.sehrNiedrig = sehrNiedrig
        self.extremNiedrig = extremNiedrig
        self.keineDaten = keineDaten
    }

    /// Stations with a definite classification (excludes the no-data bucket).
    public var classifiedCount: Int {
        keinNiedrigwasser + niedrig + sehrNiedrig + extremNiedrig
    }

    /// Mean severity across classified stations, mapped to 0–100.
    /// Class index 0…3 (none/low/veryLow/extreme), averaged, then /3·100.
    /// `nil` when no station is classified.
    public var severityScore: Double? {
        guard classifiedCount > 0 else { return nil }
        let weighted = Double(niedrig + sehrNiedrig * 2 + extremNiedrig * 3)
        return weighted / Double(classifiedCount) / 3.0 * 100.0
    }
}
