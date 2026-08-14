import Foundation

/// How far back a history chart looks.
///
/// Which windows are on offer depends on the series, and the reason is a
/// property of the sources rather than of this app:
///
/// - The **index** comes from a local log with 400-day retention, so every
///   window here is storable. Long ones simply take that long to fill, and the
///   view says how much of the window is actually covered.
/// - The **gauge** comes from PEGELONLINE, which serves a rolling ~31 days and
///   **silently returns that same month** for a longer request — verified live
///   on 2026-08-15, where `P90D` and `P365D` both answered with 2,977 points
///   covering 15 Jul to 15 Aug. Offering a year there would label one month of
///   data as twelve, which is worse than not offering it at all.
public enum TrendWindow: String, CaseIterable, Sendable {
    case week
    case month
    case quarter
    case halfYear
    case year

    public var days: Int {
        switch self {
        case .week:     return 7
        case .month:    return 30
        case .quarter:  return 90
        case .halfYear: return 182
        case .year:     return 365
        }
    }

    public var label: String {
        switch self {
        case .week:     return "7 d"
        case .month:    return "30 d"
        case .quarter:  return "3 M"
        case .halfYear: return "6 M"
        case .year:     return "12 M"
        }
    }

    /// Target point count after downsampling. The plot is roughly 285 pt wide,
    /// so beyond ~160 points the buckets are narrower than a pixel and the
    /// extra detail is invisible. Longer windows therefore get coarser buckets,
    /// not more points: daily for a month, ~3-daily for a quarter, ~5-daily for
    /// half a year, weekly for a year.
    public var maxPoints: Int {
        switch self {
        case .week:     return 160
        case .month:    return 31
        case .quarter:  return 30
        case .halfYear: return 37
        case .year:     return 52
        }
    }

    /// Windows PEGELONLINE can actually fill.
    public static let gauge: [TrendWindow] = [.week, .month]

    /// Windows the local index log can hold.
    public static let index: [TrendWindow] = allCases

    /// The longest available window no longer than this one, so switching from
    /// a 12-month index view to the gauge lands on 30 days instead of asking
    /// for a year that would come back as a month.
    public func clamped(to available: [TrendWindow]) -> TrendWindow {
        guard !available.isEmpty else { return self }
        if available.contains(self) { return self }
        return available.filter { $0.days <= days }.max { $0.days < $1.days }
            ?? available.min { $0.days < $1.days }
            ?? self
    }
}
