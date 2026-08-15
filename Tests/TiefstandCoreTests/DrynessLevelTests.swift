import XCTest
@testable import TiefstandCore

final class DrynessLevelTests: XCTestCase {

    func test_bandsUseTheCalibratedThresholds() {
        XCTAssertEqual(DrynessLevel(index: 0), .normal)
        XCTAssertEqual(DrynessLevel(index: 26.9), .normal)
        XCTAssertEqual(DrynessLevel(index: 27), .elevated)
        XCTAssertEqual(DrynessLevel(index: 37.9), .elevated)
        XCTAssertEqual(DrynessLevel(index: 38), .high)
        XCTAssertEqual(DrynessLevel(index: 51.9), .high)
        XCTAssertEqual(DrynessLevel(index: 52), .severe)
        XCTAssertEqual(DrynessLevel(index: 100), .severe)
    }

    /// The point of the recalibration. Reconstructed from NIWIS daily records
    /// for 2000–2026, the national index peaked at **64** (August 2022) and
    /// never once reached 75 — so under the old quarter-splits the top band
    /// could not be reached at all, and the driest days in a generation were
    /// labelled "High" with an unused band above them.
    func test_theOldTopBandWasUnreachable() {
        let highestObservedInTwentySevenYears = 64.0

        XCTAssertEqual(DrynessLevel(index: highestObservedInTwentySevenYears), .severe)
        XCTAssertLessThan(DrynessLevel.severeThreshold, highestObservedInTwentySevenYears)
        XCTAssertGreaterThan(75.0, highestObservedInTwentySevenYears)   // the old threshold
    }

    /// The calibration criterion: the droughts people remember must register,
    /// and ordinary years must not. Yearly maxima of the reconstructed index.
    func test_theDroughtYearsRegisterAsSevereAndOrdinaryYearsDoNot() {
        let droughts: [(year: Int, peak: Double)] = [
            (2018, 60), (2022, 64), (2025, 52), (2026, 59),
        ]
        for drought in droughts {
            XCTAssertEqual(DrynessLevel(index: drought.peak), .severe,
                           "\(drought.year) should read as severe")
        }

        let ordinary: [(year: Int, peak: Double)] = [
            (2002, 11), (2008, 11), (2013, 10), (2024, 11), (2012, 22), (2010, 24),
        ]
        for year in ordinary {
            XCTAssertNotEqual(DrynessLevel(index: year.peak), .severe,
                              "\(year.year) peaked at \(year.peak) and should not read as severe")
        }
    }

    func test_eachLevelHasADistinctLabel() {
        let labels = Set(DrynessLevel.allCases.map(\.label))
        XCTAssertEqual(labels.count, DrynessLevel.allCases.count)
    }

    func test_thresholdsAreOrdered() {
        XCTAssertLessThan(DrynessLevel.elevatedThreshold, DrynessLevel.highThreshold)
        XCTAssertLessThan(DrynessLevel.highThreshold, DrynessLevel.severeThreshold)
    }
}
