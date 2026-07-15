import Foundation

/// NIWIS low-water classification for a single station.
public enum LowWaterClass: String, Equatable, CaseIterable {
    case none = "KEIN_NIEDRIGWASSER"
    case low = "NIEDRIG"
    case veryLow = "SEHR_NIEDRIG"
    case extremelyLow = "EXTREM_NIEDRIG"

    /// 0…3 severity, matching the DomainAggregate scoring.
    public var severityIndex: Int {
        switch self {
        case .none: return 0
        case .low: return 1
        case .veryLow: return 2
        case .extremelyLow: return 3
        }
    }
}

/// Short-term direction of a station's measurement.
public enum Trend: String, Equatable {
    case rising = "STEIGEND"
    case falling = "FALLEND"
    case steady = "GLEICHBLEIBEND"
}

/// A geographic point. NIWIS encodes longitude as `x`, latitude as `y`.
public struct Coordinate: Equatable, Decodable {
    public let longitude: Double
    public let latitude: Double

    enum CodingKeys: String, CodingKey {
        case longitude = "x"
        case latitude = "y"
    }

    public init(longitude: Double, latitude: Double) {
        self.longitude = longitude
        self.latitude = latitude
    }
}

/// One station's current reading from `/karte/messstelle/{PARAM}`.
public struct StationReading: Equatable, Decodable {
    public let id: String
    public let name: String
    public let coordinate: Coordinate
    public let currentValue: Double?
    public let lowWaterClass: LowWaterClass?
    public let trend: Trend?
    public let daysBelowThreshold: Int?

    enum CodingKeys: String, CodingKey {
        case id = "nummer"
        case name = "anzeigeName"
        case coordinate = "koordinate"
        case currentValue = "aktuellerMesswert"
        case lowWaterClass = "niedrigwasserKlasse"
        case trend = "entwicklung"
        case daysBelowThreshold = "anzahlTageUnterGlw"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        coordinate = try c.decode(Coordinate.self, forKey: .coordinate)
        currentValue = try c.decodeIfPresent(Double.self, forKey: .currentValue)
        // Lenient: an unknown/absent enum value maps to nil rather than throwing,
        // so a new NIWIS class doesn't break the whole decode.
        lowWaterClass = (try c.decodeIfPresent(String.self, forKey: .lowWaterClass))
            .flatMap(LowWaterClass.init(rawValue:))
        trend = (try c.decodeIfPresent(String.self, forKey: .trend))
            .flatMap(Trend.init(rawValue:))
        daysBelowThreshold = try c.decodeIfPresent(Int.self, forKey: .daysBelowThreshold)
    }
}
