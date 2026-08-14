import XCTest
@testable import TiefstandCore

final class MapProjectionTests: XCTestCase {

    private func coordinate(lon: Double, lat: Double) -> Coordinate {
        Coordinate(longitude: lon, latitude: lat)
    }

    func test_theCentreOfTheBoxLandsInTheMiddle() throws {
        let box = MapProjection.germany
        let centre = coordinate(lon: (box.minLongitude + box.maxLongitude) / 2,
                                lat: (box.minLatitude + box.maxLatitude) / 2)

        let point = try XCTUnwrap(MapProjection.normalized(centre))

        XCTAssertEqual(point.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(point.y, 0.5, accuracy: 0.0001)
    }

    /// Screen space runs top-down, so the northern edge is y = 0.
    func test_theNorthWestCornerIsTheOrigin() throws {
        let box = MapProjection.germany
        let corner = coordinate(lon: box.minLongitude, lat: box.maxLatitude)

        let point = try XCTUnwrap(MapProjection.normalized(corner))

        XCTAssertEqual(point.x, 0, accuracy: 0.0001)
        XCTAssertEqual(point.y, 0, accuracy: 0.0001)
    }

    func test_theSouthEastCornerIsTheFarSide() throws {
        let box = MapProjection.germany
        let corner = coordinate(lon: box.maxLongitude, lat: box.minLatitude)

        let point = try XCTUnwrap(MapProjection.normalized(corner))

        XCTAssertEqual(point.x, 1, accuracy: 0.0001)
        XCTAssertEqual(point.y, 1, accuracy: 0.0001)
    }

    func test_goingNorthMovesUp() throws {
        let south = try XCTUnwrap(MapProjection.normalized(coordinate(lon: 10, lat: 48)))
        let north = try XCTUnwrap(MapProjection.normalized(coordinate(lon: 10, lat: 54)))

        XCTAssertLessThan(north.y, south.y)
    }

    func test_goingEastMovesRight() throws {
        let west = try XCTUnwrap(MapProjection.normalized(coordinate(lon: 7, lat: 51)))
        let east = try XCTUnwrap(MapProjection.normalized(coordinate(lon: 14, lat: 51)))

        XCTAssertLessThan(west.x, east.x)
    }

    /// A gauge outside the box is a data anomaly. Clamping it would park a dot
    /// on the border and claim a station there, so it is dropped instead.
    func test_coordinatesOutsideTheBoxAreDroppedRatherThanClamped() {
        XCTAssertNil(MapProjection.normalized(coordinate(lon: 2.35, lat: 48.85)))   // Paris
        XCTAssertNil(MapProjection.normalized(coordinate(lon: 10, lat: 60)))        // north of Denmark
    }

    /// Every real NIWIS discharge gauge must survive the projection — the box
    /// exists to be generous, not to filter.
    func test_theBoxCoversTheObservedRangeOfNIWISStations() {
        // Live extremes on 2026-08-15: lon 6.1–15.0, lat 47.5–54.7.
        for (lon, lat) in [(6.1, 47.5), (15.0, 54.7), (6.1, 54.7), (15.0, 47.5)] {
            XCTAssertNotNil(MapProjection.normalized(coordinate(lon: lon, lat: lat)),
                            "\(lon)/\(lat) falls outside the box")
        }
    }

    /// A degree of longitude is much shorter than a degree of latitude at 51°N.
    /// Without that correction the map draws Germany far too wide.
    func test_theMapIsTallerThanItIsWideBecauseOfTheLatitudeCorrection() {
        XCTAssertLessThan(MapProjection.aspectRatio, 1.0)
        // (9.4° lon × cos 51°) / 7.9° lat ≈ 0.75
        XCTAssertEqual(MapProjection.aspectRatio, 0.75, accuracy: 0.06)
    }

    func test_anUncorrectedProjectionWouldBeNoticeablyWider() {
        let uncorrected = (MapProjection.germany.maxLongitude - MapProjection.germany.minLongitude)
            / (MapProjection.germany.maxLatitude - MapProjection.germany.minLatitude)

        XCTAssertGreaterThan(uncorrected / MapProjection.aspectRatio, 1.5,
                             "the correction should matter by more than half again")
    }

    /// `projected` skips the bounds check on purpose — a border ring that lost
    /// a vertex would tear open where it grazes the edge of the box.
    func test_projectedKeepsCoordinatesTheBoundsCheckWouldDrop() {
        let outside = coordinate(lon: 2.35, lat: 48.85)

        XCTAssertNil(MapProjection.normalized(outside))
        XCTAssertLessThan(MapProjection.projected(outside).x, 0)
    }

    func test_everyOutlineVertexProjectsIntoThePicture() {
        for ring in GermanyOutline.coordinateRings {
            for coordinate in ring {
                let point = MapProjection.projected(coordinate)
                XCTAssertTrue((-0.02...1.02).contains(point.x)
                              && (-0.02...1.02).contains(point.y),
                              "outline vertex \(coordinate) lands off the map")
            }
        }
    }

    func test_theOutlineHasAMainlandRingAndSomeIslands() {
        let rings = GermanyOutline.coordinateRings

        XCTAssertGreaterThan(rings.count, 1, "the islands should be there")
        XCTAssertGreaterThan(rings[0].count, 150, "the mainland ring looks over-simplified")
    }

    /// Kaub sits on the Rhine in the west, a little below the middle.
    func test_aRealGaugeLandsWhereItBelongs() throws {
        let kaub = try XCTUnwrap(MapProjection.normalized(coordinate(lon: 7.764962, lat: 50.085438)))

        XCTAssertLessThan(kaub.x, 0.35, "Kaub should sit in the western third")
        XCTAssertGreaterThan(kaub.y, 0.5, "and south of the vertical middle")
    }
}
