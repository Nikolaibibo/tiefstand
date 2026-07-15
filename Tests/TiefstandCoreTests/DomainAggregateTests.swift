import XCTest
@testable import TiefstandCore

final class DomainAggregateTests: XCTestCase {

    /// Live-captured NIWIS discharge (ABFLUSS) aggregate, 2026-07-16.
    /// Mean class index (0..3) = (91·1 + 76·2 + 110·3) / 350 = 1.6371
    /// Severity score = 1.6371 / 3 · 100 = 54.57
    func test_severityScore_mapsFourClassesOntoZeroToHundred() {
        let discharge = DomainAggregate(
            keinNiedrigwasser: 73,
            niedrig: 91,
            sehrNiedrig: 76,
            extremNiedrig: 110,
            keineDaten: 4
        )

        XCTAssertEqual(discharge.severityScore ?? -1, 54.57, accuracy: 0.1)
    }

    /// NIWIS `/kreisdiagramme/{PARAM}` response shape.
    func test_decodesFromNIWISAggregateJSON() throws {
        let json = Data("""
        {"keinNiedrigwasser":73,"niedrig":91,"sehrNiedrig":76,"extremNiedrig":110,"keineDaten":4}
        """.utf8)

        let aggregate = try JSONDecoder().decode(DomainAggregate.self, from: json)

        XCTAssertEqual(aggregate.classifiedCount, 350)
        XCTAssertEqual(aggregate.severityScore ?? -1, 54.57, accuracy: 0.1)
    }
}
