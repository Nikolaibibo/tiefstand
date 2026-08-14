import Foundation

/// A PEGELONLINE gauge proposed as the history source for a NIWIS station,
/// carrying how far away it actually is.
public struct GaugeMatch: Equatable, Sendable {
    public let station: GaugeStation
    public let distanceMeters: Double

    public init(station: GaugeStation, distanceMeters: Double) {
        self.station = station
        self.distanceMeters = distanceMeters
    }

    /// Close enough to present as the same gauge, with no caveat in the UI.
    public var isExact: Bool { distanceMeters <= GaugeMatcher.exactToleranceMeters }
}

/// Bridges two systems that share no identifiers: NIWIS station IDs look like
/// `DESM_DEBY16607001`, PEGELONLINE uses UUIDs. Matching is therefore purely
/// geographic.
public enum GaugeMatcher {

    /// Within this distance the two records are treated as the same gauge.
    public static let exactToleranceMeters = 2_000.0

    /// Beyond this, no match is offered at all. A gauge 80 km away on another
    /// river is not this station's history, and showing it anyway would be a
    /// quiet lie — better an honest empty state.
    public static let maximumDistanceMeters = 25_000.0

    private static let earthRadiusMeters = 6_371_000.0

    /// Great-circle distance. Haversine rather than Core Location so this stays
    /// in a Foundation-only target and testable without a device.
    public static func distanceMeters(from a: Coordinate, to b: Coordinate) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180

        let h = sin(dLat / 2) * sin(dLat / 2)
              + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadiusMeters * atan2(sqrt(h), sqrt(1 - h))
    }

    /// The closest placeable gauge, or `nil` if the closest one is further away
    /// than `maximumDistanceMeters`.
    public static func nearest(to coordinate: Coordinate,
                               in stations: [GaugeStation]) -> GaugeMatch? {
        let candidates: [GaugeMatch] = stations.compactMap { station in
            guard let lat = station.latitude, let lon = station.longitude else { return nil }
            let distance = distanceMeters(
                from: coordinate,
                to: Coordinate(longitude: lon, latitude: lat))
            return GaugeMatch(station: station, distanceMeters: distance)
        }

        guard let closest = candidates.min(by: { $0.distanceMeters < $1.distanceMeters }),
              closest.distanceMeters <= maximumDistanceMeters
        else { return nil }
        return closest
    }
}
