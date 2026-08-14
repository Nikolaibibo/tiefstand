import XCTest
@testable import TiefstandCore

final class ReferenceGaugeTests: XCTestCase {

    private func station(_ shortname: String, uuid: String = UUID().uuidString) -> GaugeStation {
        GaugeStation(uuid: uuid, shortname: shortname, longname: shortname,
                     longitude: 7.764962, latitude: 50.085438,
                     water: GaugeStation.Water(shortname: "RHEIN", longname: "RHEIN"))
    }

    func test_resolvesTheReferenceGaugeByName() {
        let stations = [station("EMMERICH"), station("KAUB"), station("MAXAU")]

        XCTAssertEqual(ReferenceGauge.resolve(in: stations)?.shortname, "KAUB")
    }

    func test_nameMatchIsCaseInsensitive() {
        XCTAssertNotNil(ReferenceGauge.resolve(in: [station("Kaub")]))
    }

    /// Guards the fallback path: if PEGELONLINE ever renames the station, the
    /// recorded UUID still finds it rather than leaving the tab blank.
    func test_fallsBackToTheRecordedUUIDWhenTheNameChanges() {
        let renamed = station("KAUB (RHEIN)", uuid: ReferenceGauge.fallbackUUID)

        XCTAssertEqual(ReferenceGauge.resolve(in: [renamed])?.uuid, ReferenceGauge.fallbackUUID)
    }

    func test_returnsNilWhenTheGaugeIsAbsentEntirely() {
        XCTAssertNil(ReferenceGauge.resolve(in: [station("EMMERICH")]))
    }

    func test_displayNameCombinesGaugeAndWater() {
        XCTAssertEqual(ReferenceGauge.resolve(in: [station("KAUB")])?.displayName, "KAUB · RHEIN")
    }
}
