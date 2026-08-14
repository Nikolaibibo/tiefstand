import Foundation

/// A point in unit space: `0…1` left-to-right and top-to-bottom, ready to be
/// scaled into whatever rectangle the view has. Kept free of CoreGraphics so
/// the projection stays testable in a Foundation-only target.
public struct UnitPoint2D: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

/// A geographic bounding box.
public struct BoundingBox: Equatable, Sendable {
    public let minLongitude: Double
    public let maxLongitude: Double
    public let minLatitude: Double
    public let maxLatitude: Double

    public init(minLongitude: Double, maxLongitude: Double,
                minLatitude: Double, maxLatitude: Double) {
        self.minLongitude = minLongitude
        self.maxLongitude = maxLongitude
        self.minLatitude = minLatitude
        self.maxLatitude = maxLatitude
    }

    public func contains(_ coordinate: Coordinate) -> Bool {
        (minLongitude...maxLongitude).contains(coordinate.longitude)
            && (minLatitude...maxLatitude).contains(coordinate.latitude)
    }
}

/// Places gauge coordinates on the station map.
///
/// Equirectangular with a latitude correction — enough for a thumbnail a few
/// hundred points wide, and far less machinery than a real Mercator or MapKit.
public enum MapProjection {

    /// Fixed on purpose rather than fitted to the data. A box derived from
    /// whichever stations happened to answer would shift every refresh, and
    /// the whole map would twitch when a single gauge dropped out.
    ///
    /// Deliberately a little wider than the observed range (lon 6.1–15.0,
    /// lat 47.5–54.7 on 2026-08-15) so a new station near a border does not
    /// silently fall out of the picture.
    public static let germany = BoundingBox(minLongitude: 5.8, maxLongitude: 15.2,
                                            minLatitude: 47.2, maxLatitude: 55.1)

    /// A degree of longitude is `cos(latitude)` as long as a degree of
    /// latitude. At 51°N that is about 0.63, so without this the map draws
    /// Germany roughly 1.6× too wide.
    private static var latitudeCorrection: Double {
        let meanLatitude = (germany.minLatitude + germany.maxLatitude) / 2
        return cos(meanLatitude * .pi / 180)
    }

    /// Width ÷ height the view must give the map for the country to keep its
    /// shape. Roughly 0.75 — Germany is taller than it is wide.
    public static var aspectRatio: Double {
        let width = (germany.maxLongitude - germany.minLongitude) * latitudeCorrection
        let height = germany.maxLatitude - germany.minLatitude
        return width / height
    }

    /// `nil` for a coordinate outside the box. Dropping it is deliberate:
    /// clamping would put a dot on the border and assert a gauge that isn't
    /// there.
    public static func normalized(_ coordinate: Coordinate,
                                  in box: BoundingBox = germany) -> UnitPoint2D? {
        guard box.contains(coordinate) else { return nil }
        return projected(coordinate, in: box)
    }

    /// The same projection without the bounds check, for geometry that is
    /// known to belong on the map. A border ring must not lose a vertex and
    /// tear open just because it grazes the edge of the box.
    public static func projected(_ coordinate: Coordinate,
                                 in box: BoundingBox = germany) -> UnitPoint2D {
        let x = (coordinate.longitude - box.minLongitude)
            / (box.maxLongitude - box.minLongitude)
        // Screen space runs top-down, so north is y = 0.
        let y = (box.maxLatitude - coordinate.latitude)
            / (box.maxLatitude - box.minLatitude)
        return UnitPoint2D(x: x, y: y)
    }
}
