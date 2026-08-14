import XCTest
@testable import TiefstandCore

final class TrendSeriesTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_786_000_000)

    /// `count` points, `spacing` apart, starting at `from`.
    private func points(count: Int, spacing: TimeInterval,
                        from: Date, value: Double = 50) -> [TrendPoint] {
        (0..<count).map {
            TrendPoint(date: from.addingTimeInterval(Double($0) * spacing), value: value)
        }
    }

    func test_pointsOutsideTheWindowAreExcluded() {
        let end = start.addingTimeInterval(30 * 86_400)
        let inside = TrendPoint(date: start.addingTimeInterval(86_400), value: 40)
        let outside = TrendPoint(date: start.addingTimeInterval(-86_400), value: 90)

        let series = TrendSeries.make(from: [outside, inside],
                                      window: start...end,
                                      gapThreshold: 21_600,
                                      maxPoints: 160,
                                      yScale: .fixed(0...100),
                                      unit: "")

        XCTAssertEqual(series.allPoints.map(\.value), [40])
    }

    func test_inputIsSortedByDate() {
        let end = start.addingTimeInterval(7 * 86_400)
        let later = TrendPoint(date: start.addingTimeInterval(2 * 3_600), value: 20)
        let earlier = TrendPoint(date: start.addingTimeInterval(1 * 3_600), value: 10)

        let series = TrendSeries.make(from: [later, earlier],
                                      window: start...end,
                                      gapThreshold: 21_600,
                                      maxPoints: 160,
                                      yScale: .auto,
                                      unit: "cm")

        XCTAssertEqual(series.allPoints.map(\.value), [10, 20])
    }

    func test_sevenDayWindowDownsamplesTo160PointsOrFewer() {
        // 672 points = 7 days at PEGELONLINE's 15-minute cadence.
        let end = start.addingTimeInterval(7 * 86_400)
        let raw = points(count: 672, spacing: 900, from: start)

        let series = TrendSeries.make(from: raw,
                                      window: start...end,
                                      gapThreshold: 10_800,
                                      maxPoints: 160,
                                      yScale: .auto,
                                      unit: "cm")

        XCTAssertLessThanOrEqual(series.allPoints.count, 160)
        XCTAssertGreaterThan(series.allPoints.count, 100)
    }

    func test_thirtyDayWindowBucketsToAtMost31DailyPoints() {
        // 2880 points = 30 days at 15-minute cadence.
        let end = start.addingTimeInterval(30 * 86_400)
        let raw = points(count: 2_880, spacing: 900, from: start)

        let series = TrendSeries.make(from: raw,
                                      window: start...end,
                                      gapThreshold: 10_800,
                                      maxPoints: 31,
                                      yScale: .auto,
                                      unit: "cm")

        XCTAssertLessThanOrEqual(series.allPoints.count, 31)
    }

    /// Regression guard for an ordering bug that is easy to reintroduce: with
    /// 30-day daily buckets the downsampled points sit ~24 h apart, far beyond
    /// the 3 h gauge gap threshold. If gaps were detected *after* downsampling,
    /// a perfectly continuous month would shatter into 31 one-point segments
    /// and the chart would draw dots instead of a line. Split first, then
    /// downsample inside each segment.
    func test_dailyBucketsDoNotShatterAContinuousMonthIntoSegments() {
        let end = start.addingTimeInterval(30 * 86_400)
        let raw = points(count: 2_880, spacing: 900, from: start)

        let series = TrendSeries.make(from: raw,
                                      window: start...end,
                                      gapThreshold: 10_800,
                                      maxPoints: 31,
                                      yScale: .auto,
                                      unit: "cm")

        XCTAssertEqual(series.segments.count, 1)
    }

    func test_downsamplingPreservesTheFirstAndLastTimestamps() {
        let end = start.addingTimeInterval(7 * 86_400)
        let raw = points(count: 672, spacing: 900, from: start)

        let series = TrendSeries.make(from: raw,
                                      window: start...end,
                                      gapThreshold: 10_800,
                                      maxPoints: 160,
                                      yScale: .auto,
                                      unit: "cm")

        XCTAssertEqual(series.allPoints.first?.date, raw.first?.date)
        XCTAssertEqual(series.allPoints.last?.date, raw.last?.date)
    }

    func test_downsamplingAveragesValuesWithinABucket() {
        let end = start.addingTimeInterval(2 * 86_400)
        let raw = [
            TrendPoint(date: start.addingTimeInterval(3_600), value: 10),
            TrendPoint(date: start.addingTimeInterval(7_200), value: 30),
            TrendPoint(date: start.addingTimeInterval(86_400 + 3_600), value: 100),
        ]

        let series = TrendSeries.make(from: raw,
                                      window: start...end,
                                      gapThreshold: 2 * 86_400,   // no split
                                      maxPoints: 2,
                                      yScale: .auto,
                                      unit: "")

        XCTAssertEqual(series.allPoints.map(\.value), [20, 100])
    }

    func test_contiguousPointsProduceExactlyOneSegment() {
        let end = start.addingTimeInterval(7 * 86_400)
        let raw = points(count: 24, spacing: 7_200, from: start)   // every 2 h

        let series = TrendSeries.make(from: raw,
                                      window: start...end,
                                      gapThreshold: 21_600,
                                      maxPoints: 160,
                                      yScale: .fixed(0...100),
                                      unit: "")

        XCTAssertEqual(series.segments.count, 1)
    }

    func test_aGapLongerThanTheThresholdSplitsTheSeriesInTwo() {
        let end = start.addingTimeInterval(7 * 86_400)
        let before = points(count: 5, spacing: 7_200, from: start)
        // 24 h later — well past the 6 h index threshold.
        let after = points(count: 5, spacing: 7_200,
                           from: start.addingTimeInterval(5 * 7_200 + 86_400))

        let series = TrendSeries.make(from: before + after,
                                      window: start...end,
                                      gapThreshold: 21_600,
                                      maxPoints: 160,
                                      yScale: .fixed(0...100),
                                      unit: "")

        XCTAssertEqual(series.segments.count, 2)
        XCTAssertEqual(series.segments[0].points.count, 5)
        XCTAssertEqual(series.segments[1].points.count, 5)
    }

    func test_coverageIsOneForAFullyCoveredWindow() {
        let end = start.addingTimeInterval(7 * 86_400)
        let raw = points(count: 85, spacing: 7_200, from: start)   // 7 days at 2 h

        let series = TrendSeries.make(from: raw,
                                      window: start...end,
                                      gapThreshold: 21_600,
                                      maxPoints: 160,
                                      yScale: .fixed(0...100),
                                      unit: "")

        XCTAssertEqual(series.coverage, 1.0, accuracy: 0.02)
    }

    func test_coverageReflectsTwoRecordedDaysOutOfThirty() {
        let end = start.addingTimeInterval(30 * 86_400)
        // Two days of samples at the 2 h poll cadence, at the end of the window.
        let raw = points(count: 25, spacing: 7_200,
                         from: end.addingTimeInterval(-2 * 86_400))

        let series = TrendSeries.make(from: raw,
                                      window: start...end,
                                      gapThreshold: 21_600,
                                      maxPoints: 31,
                                      yScale: .fixed(0...100),
                                      unit: "")

        XCTAssertEqual(series.coverage, 2.0 / 30.0, accuracy: 0.01)
    }

    func test_anEmptyInputProducesAnEmptySeriesWithZeroCoverage() {
        let end = start.addingTimeInterval(30 * 86_400)

        let series = TrendSeries.make(from: [],
                                      window: start...end,
                                      gapThreshold: 21_600,
                                      maxPoints: 31,
                                      yScale: .fixed(0...100),
                                      unit: "")

        XCTAssertTrue(series.isEmpty)
        XCTAssertEqual(series.coverage, 0)
    }

    func test_aSingleSampleIsKeptButCoversAlmostNothing() {
        let end = start.addingTimeInterval(30 * 86_400)
        let raw = [TrendPoint(date: end.addingTimeInterval(-3_600), value: 47)]

        let series = TrendSeries.make(from: raw,
                                      window: start...end,
                                      gapThreshold: 21_600,
                                      maxPoints: 31,
                                      yScale: .fixed(0...100),
                                      unit: "")

        XCTAssertEqual(series.allPoints.count, 1)
        XCTAssertEqual(series.coverage, 0, accuracy: 0.001)
    }
}
