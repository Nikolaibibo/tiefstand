import XCTest
@testable import TiefstandCore

/// A test double that serves canned aggregates and throws for the rest.
private struct StubProvider: DataProvider {
    var discharge: DomainAggregate?
    var groundwater: DomainAggregate?

    func aggregate(for domain: WaterDomain) async throws -> DomainAggregate {
        switch domain {
        case .discharge:
            if let discharge { return discharge }
        case .groundwater:
            if let groundwater { return groundwater }
        default:
            break
        }
        throw DataProviderError.noData
    }

    func stations(for domain: WaterDomain) async throws -> [StationReading] { [] }
}

final class DrynessIndexResilienceTests: XCTestCase {

    private let discharge = DomainAggregate(
        keinNiedrigwasser: 73, niedrig: 91, sehrNiedrig: 76, extremNiedrig: 110, keineDaten: 4)

    func test_currentDrynessIndex_fallsBackToDischargeWhenGroundwaterFails() async throws {
        let provider = StubProvider(discharge: discharge, groundwater: nil)

        let index = try await provider.currentDrynessIndex()

        XCTAssertEqual(index.value, discharge.severityScore ?? -1, accuracy: 0.1)
        XCTAssertNil(index.groundwaterScore)
    }

    func test_currentDrynessIndex_throwsWhenBothDomainsFail() async {
        let provider = StubProvider(discharge: nil, groundwater: nil)

        do {
            _ = try await provider.currentDrynessIndex()
            XCTFail("expected currentDrynessIndex to throw when no domain is available")
        } catch {
            // expected
        }
    }
}
