import XCTest
@testable import TiefstandCore

/// Live integration test against the NIWIS API. Skips (does not fail) when
/// the network or endpoint is unavailable, so offline runs stay green.
final class NIWISProviderTests: XCTestCase {

    func test_liveDrynessIndexIsInRange() async throws {
        let provider = NIWISProvider()
        let index: DrynessIndex
        do {
            index = try await provider.currentDrynessIndex()
        } catch {
            throw XCTSkip("NIWIS unreachable: \(error)")
        }

        XCTAssert((0...100).contains(index.value), "index out of range: \(index.value)")
        XCTAssertNotNil(index.dischargeScore)
        XCTAssertNotNil(index.groundwaterScore)
    }

    func test_liveStationsCarryCoordinatesAndClass() async throws {
        let provider = NIWISProvider()
        let stations: [StationReading]
        do {
            stations = try await provider.stations(for: .discharge)
        } catch {
            throw XCTSkip("NIWIS unreachable: \(error)")
        }

        XCTAssertFalse(stations.isEmpty)
        let first = try XCTUnwrap(stations.first)
        XCTAssert((-180...180).contains(first.coordinate.longitude))
        XCTAssert((-90...90).contains(first.coordinate.latitude))
    }
}
