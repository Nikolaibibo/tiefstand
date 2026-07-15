import XCTest
@testable import TiefstandCore

final class StationReadingTests: XCTestCase {

    /// Real NIWIS `/karte/messstelle/{PARAM}` record, 2026-07-16.
    private let inkofen = Data("""
    {"nummer":"DESM_DEBY16607001","anzeigeName":"Inkofen (Amper)",
     "koordinate":{"x":11.8655,"y":48.4607},"aktuellerMesswert":16.9,
     "niedrigwasserKlasse":"EXTREM_NIEDRIG","entwicklung":"GLEICHBLEIBEND",
     "anzahlTageUnterGlw":null,"hatSchifffahrtsrelevantenKennwert":false}
    """.utf8)

    func test_decodesFromNIWISStationJSON() throws {
        let station = try JSONDecoder().decode(StationReading.self, from: inkofen)

        XCTAssertEqual(station.id, "DESM_DEBY16607001")
        XCTAssertEqual(station.name, "Inkofen (Amper)")
        XCTAssertEqual(station.coordinate.latitude, 48.4607, accuracy: 0.0001)
        XCTAssertEqual(station.coordinate.longitude, 11.8655, accuracy: 0.0001)
        XCTAssertEqual(station.currentValue, 16.9)
        XCTAssertEqual(station.lowWaterClass, .extremelyLow)
        XCTAssertEqual(station.trend, .steady)
        XCTAssertNil(station.daysBelowThreshold)
    }
}
