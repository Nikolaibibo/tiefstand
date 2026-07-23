import XCTest
@testable import TiefstandCore

final class WidgetRefreshTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    /// A successful fetch schedules the next timeline reload one hour out,
    /// matching NIWIS's classification cadence (no point polling faster).
    func test_refreshAfterSuccessIsOneHourOut() {
        let next = WidgetRefresh.next(after: now, success: true)
        XCTAssertEqual(next.timeIntervalSince(now), 3600, accuracy: 0.001)
    }

    /// A failed fetch retries sooner than the steady-state hour, so a transient
    /// outage doesn't freeze the widget for a full interval.
    func test_refreshAfterFailureRetriesSoonerThanAnHour() {
        let next = WidgetRefresh.next(after: now, success: false)
        let delay = next.timeIntervalSince(now)
        XCTAssertGreaterThan(delay, 0)
        XCTAssertLessThan(delay, 3600)
    }
}
