import XCTest
@testable import TiefstandCore

final class DrynessLevelTests: XCTestCase {

    func test_bandsSplitZeroToHundredAtQuarters() {
        XCTAssertEqual(DrynessLevel(index: 0), .normal)
        XCTAssertEqual(DrynessLevel(index: 24.9), .normal)
        XCTAssertEqual(DrynessLevel(index: 25), .elevated)
        XCTAssertEqual(DrynessLevel(index: 49.1), .elevated)   // Germany right now
        XCTAssertEqual(DrynessLevel(index: 50), .high)
        XCTAssertEqual(DrynessLevel(index: 74.9), .high)
        XCTAssertEqual(DrynessLevel(index: 75), .severe)
        XCTAssertEqual(DrynessLevel(index: 100), .severe)
    }

    func test_eachLevelHasADistinctLabel() {
        let labels = Set(DrynessLevel.allCases.map(\.label))
        XCTAssertEqual(labels.count, DrynessLevel.allCases.count)
    }
}
