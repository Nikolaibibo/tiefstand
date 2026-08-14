import Foundation

/// A single plotted observation.
public struct TrendPoint: Equatable, Sendable {
    public let date: Date
    public let value: Double

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

/// A contiguous run of points. A recording gap ends one segment and starts the
/// next, so the renderer draws a break instead of a straight line through data
/// that was never measured.
public struct TrendSegment: Equatable, Sendable {
    public let points: [TrendPoint]

    public init(points: [TrendPoint]) {
        self.points = points
    }
}

/// How the vertical axis is chosen.
public enum YScale: Equatable, Sendable {
    /// The Dryness Index is defined on 0–100; pinning the axis keeps the four
    /// severity bands meaningful and stops a flat week from looking dramatic.
    case fixed(ClosedRange<Double>)
    /// Gauge readings are centimetres with no natural bounds — fit the data.
    case auto
}

/// Drawable geometry, decoupled from where the numbers came from. The index
/// series is read from disk and the gauge series from the network, but the
/// chart only ever sees this.
public struct TrendSeries: Equatable, Sendable {
    public let segments: [TrendSegment]
    public let window: ClosedRange<Date>
    public let yScale: YScale
    public let unit: String
    /// 0…1 — how much of the window actually has data behind it. Drives the
    /// "n of 30 days" label on the index tab.
    public let coverage: Double

    public init(segments: [TrendSegment],
                window: ClosedRange<Date>,
                yScale: YScale,
                unit: String,
                coverage: Double) {
        self.segments = segments
        self.window = window
        self.yScale = yScale
        self.unit = unit
        self.coverage = coverage
    }

    public var allPoints: [TrendPoint] { segments.flatMap(\.points) }
    public var isEmpty: Bool { allPoints.isEmpty }

    /// Smallest and largest plotted value, or `nil` when empty.
    public var valueRange: ClosedRange<Double>? {
        let values = allPoints.map(\.value)
        guard let lo = values.min(), let hi = values.max() else { return nil }
        return lo == hi ? (lo - 1)...(hi + 1) : lo...hi
    }
}

public extension TrendSeries {

    /// Filter → **split on gaps** → downsample within each segment. Pure; no
    /// clock, no I/O.
    ///
    /// The order matters and is the one thing not to rearrange here. Gaps are
    /// found in the *raw* data, because downsampled points are deliberately far
    /// apart — a 30-day window buckets to one point per day, and comparing
    /// those 24 h spacings against a 3 h threshold would turn an unbroken month
    /// into 31 isolated dots.
    ///
    /// - Parameters:
    ///   - gapThreshold: an interval longer than this is a hole, not a line.
    ///     6 h for the index (3× its 2 h poll), 3 h for the gauge.
    ///   - maxPoints: 160 for a 7-day window, 31 for a 30-day window — the
    ///     latter being exactly one bucket per day.
    static func make(from points: [TrendPoint],
                     window: ClosedRange<Date>,
                     gapThreshold: TimeInterval,
                     maxPoints: Int,
                     yScale: YScale,
                     unit: String) -> TrendSeries {
        let inWindow = points
            .filter { window.contains($0.date) }
            .sorted { $0.date < $1.date }

        var segments = split(inWindow, gapThreshold: gapThreshold).map {
            TrendSegment(points: downsample($0.points, window: window, maxPoints: maxPoints))
        }
        pinEnds(of: &segments, to: inWindow)

        return TrendSeries(
            segments: segments,
            window: window,
            yScale: yScale,
            unit: unit,
            coverage: coverage(of: inWindow, in: window, gapThreshold: gapThreshold))
    }

    /// Time-bucket averaging on a grid aligned to the window start, so the
    /// output is stable between refreshes rather than shifting with every new
    /// point — and so segments downsampled separately still line up on one grid.
    private static func downsample(_ points: [TrendPoint],
                                   window: ClosedRange<Date>,
                                   maxPoints: Int) -> [TrendPoint] {
        guard maxPoints > 0, points.count > maxPoints else { return points }

        let span = window.upperBound.timeIntervalSince(window.lowerBound)
        guard span > 0 else { return points }
        let bucketWidth = span / Double(maxPoints)

        var buckets: [Int: [TrendPoint]] = [:]
        for point in points {
            let offset = point.date.timeIntervalSince(window.lowerBound)
            let bucket = min(maxPoints - 1, max(0, Int(offset / bucketWidth)))
            buckets[bucket, default: []].append(point)
        }

        return buckets.keys.sorted().compactMap { key in
            guard let group = buckets[key], !group.isEmpty else { return nil }
            let meanValue = group.reduce(0) { $0 + $1.value } / Double(group.count)
            let meanDate = Date(timeIntervalSinceReferenceDate:
                group.reduce(0) { $0 + $1.date.timeIntervalSinceReferenceDate } / Double(group.count))
            return TrendPoint(date: meanDate, value: meanValue)
        }
    }

    /// Anchors the very first and very last plotted points to the real
    /// observations, so a downsampled curve doesn't visibly shrink away from
    /// the edges of the chart. Only the outer ends move; interior bucket dates
    /// stay on the grid.
    private static func pinEnds(of segments: inout [TrendSegment], to raw: [TrendPoint]) {
        guard !segments.isEmpty, let firstRaw = raw.first, let lastRaw = raw.last else { return }

        if var points = segments.first?.points, let head = points.first {
            points[0] = TrendPoint(date: firstRaw.date, value: head.value)
            segments[0] = TrendSegment(points: points)
        }
        if var points = segments.last?.points, let tail = points.last {
            points[points.count - 1] = TrendPoint(date: lastRaw.date, value: tail.value)
            segments[segments.count - 1] = TrendSegment(points: points)
        }
    }

    private static func split(_ points: [TrendPoint],
                              gapThreshold: TimeInterval) -> [TrendSegment] {
        guard !points.isEmpty else { return [] }

        var segments: [TrendSegment] = []
        var current: [TrendPoint] = [points[0]]

        for point in points.dropFirst() {
            let previous = current[current.count - 1].date
            if point.date.timeIntervalSince(previous) > gapThreshold {
                segments.append(TrendSegment(points: current))
                current = [point]
            } else {
                current.append(point)
            }
        }
        segments.append(TrendSegment(points: current))
        return segments
    }

    /// Sums the intervals that are short enough to count as "covered" and
    /// divides by the window length. Deliberately computed from the raw points,
    /// before downsampling, so it describes the recording and not the drawing.
    private static func coverage(of points: [TrendPoint],
                                 in window: ClosedRange<Date>,
                                 gapThreshold: TimeInterval) -> Double {
        let span = window.upperBound.timeIntervalSince(window.lowerBound)
        guard span > 0, points.count > 1 else { return 0 }

        let covered = zip(points, points.dropFirst()).reduce(0.0) { total, pair in
            let delta = pair.1.date.timeIntervalSince(pair.0.date)
            return delta <= gapThreshold ? total + delta : total
        }
        return min(1, covered / span)
    }
}
