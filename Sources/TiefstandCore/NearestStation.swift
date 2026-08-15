import Foundation

/// Picks the NIWIS station closest to a point.
///
/// Distinct from `GaugeMatcher`, which bridges NIWIS to PEGELONLINE and carries
/// the tolerances that bridging needs. This one stays inside NIWIS: given where
/// you are, which of its stations is nearest. No tolerance, because there is
/// nothing to reconcile — only a bounds check, since "the nearest German gauge"
/// stops meaning anything once you are not in Germany.
public enum NearestStation {

    public struct Match: Equatable, Sendable {
        public let station: StationReading
        public let distanceMeters: Double

        public init(station: StationReading, distanceMeters: Double) {
            self.station = station
            self.distanceMeters = distanceMeters
        }

        /// "4.2 km", or metres below one kilometre.
        public var distanceLabel: String {
            distanceMeters < 1_000
                ? "\(Int(distanceMeters.rounded())) m away"
                : String(format: "%.1f km away", distanceMeters / 1_000)
        }
    }

    /// `nil` when the point lies outside Germany, or when no station has
    /// usable coordinates. Callers fall back to their previous choice rather
    /// than showing nothing.
    public static func to(_ coordinate: Coordinate,
                          in stations: [StationReading]) -> Match? {
        guard MapProjection.germany.contains(coordinate) else { return nil }

        return stations
            .map { Match(station: $0,
                         distanceMeters: GaugeMatcher.distanceMeters(from: coordinate,
                                                                     to: $0.coordinate)) }
            .min { $0.distanceMeters < $1.distanceMeters }
    }
}
