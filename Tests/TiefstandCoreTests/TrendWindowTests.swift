import XCTest
@testable import TiefstandCore

final class TrendWindowTests: XCTestCase {

    func test_windowsRunFromShortestToLongest() {
        XCTAssertEqual(TrendWindow.allCases.map(\.days), [7, 30, 90, 182, 365])
    }

    func test_everyWindowHasAShortLabel() {
        XCTAssertEqual(TrendWindow.allCases.map(\.label), ["7 d", "30 d", "3 M", "6 M", "12 M"])
    }

    /// A longer window must not mean more points — the chart is ~285 pt wide
    /// and the buckets grow instead.
    func test_bucketsGrowWithTheWindowRatherThanThePointCount() {
        for window in TrendWindow.allCases {
            XCTAssertLessThanOrEqual(window.maxPoints, 160, "\(window) asks for too many points")
            XCTAssertGreaterThanOrEqual(window.maxPoints, 30, "\(window) asks for too few points")
        }
        // A month buckets to one point per day; a year must be coarser than that.
        XCTAssertEqual(TrendWindow.month.maxPoints, 31)
        XCTAssertLessThan(Double(TrendWindow.year.maxPoints) / 365.0,
                          Double(TrendWindow.month.maxPoints) / 30.0)
    }

    /// PEGELONLINE serves a rolling ~31 days and **silently returns that same
    /// month** for `P90D` or `P365D` — verified live 2026-08-15, both gave 2977
    /// points covering 15 Jul to 15 Aug. Offering a longer window on the gauge
    /// would therefore label a month of data as a year.
    func test_gaugeOffersOnlyWindowsPEGELONLINECanActuallyFill() {
        XCTAssertEqual(TrendWindow.gauge, [.week, .month])
        for window in TrendWindow.gauge {
            XCTAssertLessThanOrEqual(window.days, 31)
        }
    }

    /// The index is read from a local log with 400-day retention, so a year is
    /// storable — it just takes a year to fill.
    func test_indexOffersEveryWindowAndStaysWithinRetention() {
        XCTAssertEqual(TrendWindow.index, TrendWindow.allCases)
        let retentionDays = Int(IndexHistoryStore.defaultRetention / 86_400)
        for window in TrendWindow.index {
            XCTAssertLessThanOrEqual(window.days, retentionDays)
        }
    }

    func test_clampingKeepsAWindowThatIsAlreadyAvailable() {
        XCTAssertEqual(TrendWindow.month.clamped(to: TrendWindow.gauge), .month)
    }

    /// Switching from a 12-month index view to the gauge must not silently ask
    /// PEGELONLINE for a year — it falls back to the longest window the gauge
    /// can honestly show.
    func test_clampingFallsBackToTheLongestAvailableWindow() {
        XCTAssertEqual(TrendWindow.year.clamped(to: TrendWindow.gauge), .month)
        XCTAssertEqual(TrendWindow.quarter.clamped(to: TrendWindow.gauge), .month)
    }

    func test_clampingAnEmptyListReturnsTheWindowUnchanged() {
        XCTAssertEqual(TrendWindow.year.clamped(to: []), .year)
    }
}
