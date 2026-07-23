import Foundation

/// Timeline reload cadence for the desktop widget. Kept in Core (Foundation-only)
/// so the policy is unit-testable without pulling in WidgetKit.
public enum WidgetRefresh {
    /// Steady-state interval. NIWIS reclassifies at most hourly, so polling
    /// faster would just burn WidgetKit's refresh budget for no fresher data.
    public static let successInterval: TimeInterval = 3600

    /// Shorter retry after a failed fetch, so a transient outage doesn't leave
    /// the widget frozen for a full hour.
    public static let retryInterval: TimeInterval = 900

    /// The next timeline reload date given whether the last fetch succeeded.
    public static func next(after date: Date, success: Bool) -> Date {
        date.addingTimeInterval(success ? successInterval : retryInterval)
    }
}
