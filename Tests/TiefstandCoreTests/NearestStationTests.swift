import XCTest
@testable import TiefstandCore

final class NearestStationTests: XCTestCase {

    private func station(_ name: String, lat: Double, lon: Double) throws -> StationReading {
        let json = Data("""
        {"nummer":"\(name)","anzeigeName":"\(name)",
         "koordinate":{"x":\(lon),"y":\(lat)},
         "aktuellerMesswert":42.0,"niedrigwasserKlasse":"NIEDRIG"}
        """.utf8)
        return try JSONDecoder().decode(StationReading.self, from: json)
    }

    /// Börnsen, on the Hamburg boundary.
    private let home = Coordinate(longitude: 10.3, latitude: 53.47)

    func test_picksTheClosestStation() throws {
        let near = try station("Boizenburg", lat: 53.38, lon: 10.72)
        let far = try station("Passau", lat: 48.57, lon: 13.46)

        let match = NearestStation.to(home, in: [far, near])

        XCTAssertEqual(match?.station.name, "Boizenburg")
    }

    func test_theDistanceIsReported() throws {
        let near = try station("Boizenburg", lat: 53.38, lon: 10.72)

        let match = try XCTUnwrap(NearestStation.to(home, in: [near]))

        // ~30 km east-south-east of Börnsen.
        XCTAssertEqual(match.distanceMeters, 30_000, accuracy: 4_000)
    }

    /// "The nearest German gauge" stops meaning anything once you are not in
    /// Germany, so the caller keeps whatever it had.
    func test_aPointOutsideGermanyHasNoNearestStation() throws {
        let near = try station("Boizenburg", lat: 53.38, lon: 10.72)

        XCTAssertNil(NearestStation.to(Coordinate(longitude: 2.35, latitude: 48.85), in: [near]))
        XCTAssertNil(NearestStation.to(Coordinate(longitude: -0.13, latitude: 51.51), in: [near]))
    }

    func test_noStationsMeansNoMatch() {
        XCTAssertNil(NearestStation.to(home, in: []))
    }

    func test_distanceReadsInMetresBelowAKilometreAndKilometresAbove() throws {
        let close = NearestStation.Match(station: try station("A", lat: 53.47, lon: 10.3),
                                         distanceMeters: 420)
        let far = NearestStation.Match(station: try station("B", lat: 53.47, lon: 10.3),
                                       distanceMeters: 4_240)

        XCTAssertEqual(close.distanceLabel, "420 m away")
        XCTAssertEqual(far.distanceLabel, "4.2 km away")
    }
}
