import XCTest
@testable import TiefstandCore

final class DrynessMetricTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_786_000_000)

    private func sample(_ offsetHours: Double,
                        index: Double,
                        discharge: Double?,
                        groundwater: Double?) -> DrynessSample {
        DrynessSample(timestamp: t0.addingTimeInterval(offsetHours * 3_600),
                      index: index, dischargeScore: discharge, groundwaterScore: groundwater)
    }

    func test_indexPointsUseEverySample() {
        let samples = [sample(0, index: 40, discharge: 44, groundwater: 36),
                       sample(2, index: 62, discharge: 71, groundwater: 53)]

        XCTAssertEqual(samples.points(for: .index).map(\.value), [40, 62])
    }

    func test_dischargePointsUseTheDischargeScore() {
        let samples = [sample(0, index: 40, discharge: 44, groundwater: 36),
                       sample(2, index: 62, discharge: 71, groundwater: 53)]

        XCTAssertEqual(samples.points(for: .discharge).map(\.value), [44, 71])
    }

    func test_groundwaterPointsUseTheGroundwaterScore() {
        let samples = [sample(0, index: 40, discharge: 44, groundwater: 36),
                       sample(2, index: 62, discharge: 71, groundwater: 53)]

        XCTAssertEqual(samples.points(for: .groundwater).map(\.value), [36, 53])
    }

    /// A domain can be missing from a refresh — `DrynessIndex.combined` is
    /// deliberately resilient to that and records `nil`. Such a sample has no
    /// point on that curve; it must be skipped, not read as zero, which would
    /// draw a dive to "no drought at all".
    func test_samplesWithoutADomainScoreAreSkippedOnThatCurveOnly() {
        let samples = [sample(0, index: 40, discharge: 44, groundwater: nil),
                       sample(2, index: 62, discharge: nil, groundwater: 53)]

        XCTAssertEqual(samples.points(for: .index).count, 2)
        XCTAssertEqual(samples.points(for: .discharge).map(\.value), [44])
        XCTAssertEqual(samples.points(for: .groundwater).map(\.value), [53])
    }

    func test_pointsCarryTheSampleTimestamp() {
        let samples = [sample(3, index: 40, discharge: 44, groundwater: 36)]

        XCTAssertEqual(samples.points(for: .discharge).first?.date,
                       t0.addingTimeInterval(3 * 3_600))
    }

    func test_noSamplesYieldNoPoints() {
        let samples: [DrynessSample] = []

        for metric in DrynessMetric.allCases {
            XCTAssertTrue(samples.points(for: metric).isEmpty)
        }
    }

    func test_everyMetricHasALabel() {
        XCTAssertEqual(DrynessMetric.index.label, "Index")
        XCTAssertEqual(DrynessMetric.discharge.label, "Discharge")
        XCTAssertEqual(DrynessMetric.groundwater.label, "Groundwater")
    }
}
