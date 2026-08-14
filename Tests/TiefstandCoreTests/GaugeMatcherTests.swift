import XCTest
@testable import TiefstandCore

final class GaugeMatcherTests: XCTestCase {

    private func station(_ name: String, lat: Double?, lon: Double?) -> GaugeStation {
        GaugeStation(uuid: name.lowercased(), shortname: name, longname: name,
                     longitude: lon, latitude: lat,
                     water: GaugeStation.Water(shortname: "ALLER", longname: "ALLER"))
    }

    private let celle = Coordinate(longitude: 10.062164, latitude: 52.622706)

    func test_oneDegreeOfLatitudeIsAboutOneHundredElevenKilometres() {
        let distance = GaugeMatcher.distanceMeters(
            from: Coordinate(longitude: 10, latitude: 52),
            to: Coordinate(longitude: 10, latitude: 53))

        XCTAssertEqual(distance, 111_195, accuracy: 1_112)   // within 1 %
    }

    func test_identicalCoordinatesAreZeroApart() {
        XCTAssertEqual(GaugeMatcher.distanceMeters(from: celle, to: celle), 0, accuracy: 0.001)
    }

    func test_picksTheNearestOfSeveralGauges() {
        let near = station("NEAR", lat: 52.6228, lon: 10.0622)      // ~10 m
        let far = station("FAR", lat: 52.70, lon: 10.30)            // ~17 km

        let match = GaugeMatcher.nearest(to: celle, in: [far, near])

        XCTAssertEqual(match?.station.shortname, "NEAR")
    }

    func test_aGaugeWithinTwoKilometresCountsAsTheSameStation() {
        // ~1.1 km north.
        let match = GaugeMatcher.nearest(to: celle, in: [station("CELLE", lat: 52.6327, lon: 10.062164)])

        XCTAssertNotNil(match)
        XCTAssertTrue(match!.isExact)
    }

    func test_aGaugeJustBeyondTwoKilometresIsStillReturnedButNotExact() {
        // ~2.8 km north.
        let match = GaugeMatcher.nearest(to: celle, in: [station("NEARBY", lat: 52.6479, lon: 10.062164)])

        XCTAssertNotNil(match)
        XCTAssertFalse(match!.isExact)
        XCTAssertGreaterThan(match!.distanceMeters, GaugeMatcher.exactToleranceMeters)
    }

    func test_theNearestGaugeBeyondTwentyFiveKilometresIsRejected() {
        // ~55 km north — a different river, not "this station's history".
        let match = GaugeMatcher.nearest(to: celle, in: [station("ELSEWHERE", lat: 53.12, lon: 10.062164)])

        XCTAssertNil(match)
    }

    func test_stationsWithoutCoordinatesAreSkipped() {
        let placeable = station("NEAR", lat: 52.6228, lon: 10.0622)
        let unplaceable = station("NOWHERE", lat: nil, lon: nil)

        let match = GaugeMatcher.nearest(to: celle, in: [unplaceable, placeable])

        XCTAssertEqual(match?.station.shortname, "NEAR")
    }

    func test_anEmptyStationListHasNoMatch() {
        XCTAssertNil(GaugeMatcher.nearest(to: celle, in: []))
    }
}
