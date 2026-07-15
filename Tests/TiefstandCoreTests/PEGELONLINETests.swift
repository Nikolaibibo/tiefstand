import XCTest
@testable import TiefstandCore

final class PEGELONLINETests: XCTestCase {

    /// Shape of `stations.json?includeTimeseries=true&includeCurrentMeasurement=true`.
    /// PEGELONLINE only classifies water level (W) as low/normal/high → the
    /// fallback aggregate is coarse (no very-low / extreme buckets).
    func test_mapsWaterLevelStatesToAggregate() throws {
        let json = Data("""
        [
         {"timeseries":[{"shortname":"W","currentMeasurement":{"stateMnwMhw":"low"}}]},
         {"timeseries":[{"shortname":"W","currentMeasurement":{"stateMnwMhw":"normal"}}]},
         {"timeseries":[{"shortname":"W","currentMeasurement":{"stateMnwMhw":"high"}}]},
         {"timeseries":[{"shortname":"W","currentMeasurement":{"stateMnwMhw":"unknown"}}]},
         {"timeseries":[{"shortname":"Q","currentMeasurement":{"stateMnwMhw":"low"}}]}
        ]
        """.utf8)

        let aggregate = try PEGELONLINEMapper.aggregate(from: json)

        XCTAssertEqual(aggregate.niedrig, 1)            // one "low"
        XCTAssertEqual(aggregate.keinNiedrigwasser, 2)  // normal + high
        XCTAssertEqual(aggregate.keineDaten, 2)         // unknown + no-W station
        XCTAssertEqual(aggregate.sehrNiedrig, 0)
        XCTAssertEqual(aggregate.extremNiedrig, 0)
    }
}
