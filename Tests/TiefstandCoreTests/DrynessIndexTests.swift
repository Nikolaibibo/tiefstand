import XCTest
@testable import TiefstandCore

final class DrynessIndexTests: XCTestCase {

    // Live-captured NIWIS aggregates, 2026-07-16.
    private let discharge = DomainAggregate(
        keinNiedrigwasser: 73, niedrig: 91, sehrNiedrig: 76, extremNiedrig: 110, keineDaten: 4)
    private let groundwater = DomainAggregate(
        keinNiedrigwasser: 80, niedrig: 44, sehrNiedrig: 59, extremNiedrig: 46, keineDaten: 3)

    /// discharge 54.57, groundwater 43.67 → mean 49.12
    func test_combined_isFiftyFiftyMeanOfDomainScores() throws {
        let index = try XCTUnwrap(DrynessIndex.combined(discharge: discharge, groundwater: groundwater))
        XCTAssertEqual(index.value, 49.12, accuracy: 0.1)
    }

    func test_combined_ignoresDomainWithoutData() throws {
        let empty = DomainAggregate(
            keinNiedrigwasser: 0, niedrig: 0, sehrNiedrig: 0, extremNiedrig: 0, keineDaten: 5)
        let index = try XCTUnwrap(DrynessIndex.combined(discharge: discharge, groundwater: empty))
        XCTAssertEqual(index.value, discharge.severityScore ?? -1, accuracy: 0.001)
    }

    func test_combined_isNilWhenNoDomainHasData() {
        let empty = DomainAggregate(
            keinNiedrigwasser: 0, niedrig: 0, sehrNiedrig: 0, extremNiedrig: 0, keineDaten: 5)
        XCTAssertNil(DrynessIndex.combined(discharge: empty, groundwater: empty))
    }
}
