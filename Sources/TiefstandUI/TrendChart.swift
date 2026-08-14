import SwiftUI
import TiefstandCore

/// Line chart for a `TrendSeries`, drawn with `Canvas` to match `WaveGauge`
/// and `Donut`. `Canvas` is fine here — the restriction only applies to the
/// `MenuBarExtra` label.
///
/// Each `TrendSegment` becomes its own path, so a recording gap shows as a
/// break rather than a line through data that was never measured.
public struct TrendChart: View {
    private let series: TrendSeries
    private let showsSeverityBands: Bool

    /// The point under the cursor, or `nil` when not hovering.
    @State private var hovered: TrendPoint?

    /// - Parameter showsSeverityBands: draws the four `DrynessLevel` bands
    ///   behind the curve. Meaningful for the 0–100 index, meaningless for
    ///   centimetres.
    public init(series: TrendSeries, showsSeverityBands: Bool) {
        self.series = series
        self.showsSeverityBands = showsSeverityBands
    }

    private var bounds: ClosedRange<Double> {
        switch series.yScale {
        case .fixed(let range):
            return range
        case .auto:
            guard let range = series.valueRange else { return 0...1 }
            let padding = max(1, (range.upperBound - range.lowerBound) * 0.12)
            return (range.lowerBound - padding)...(range.upperBound + padding)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    plot
                    yAxisLabels
                    if let hovered { readout(for: hovered) }
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        hovered = nearestPoint(toX: location.x, width: geometry.size.width)
                    case .ended:
                        hovered = nil
                    }
                }
            }
            xAxisLabels
        }
    }

    private var plot: some View {
        Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            if showsSeverityBands { drawSeverityBands(&ctx, in: rect) }
            drawGridLines(&ctx, in: rect)
            for segment in series.segments {
                drawSegment(segment, &ctx, in: rect)
            }
            if let hovered { drawCrosshair(hovered, &ctx, in: rect) }
        }
    }

    // MARK: axes

    /// Three ticks — top, middle, bottom — laid over the right edge of the plot
    /// rather than in a gutter, so the 320 pt popover keeps its drawing width.
    private var yAxisLabels: some View {
        let range = bounds
        return VStack(spacing: 0) {
            axisText(range.upperBound)
            Spacer(minLength: 0)
            axisText((range.lowerBound + range.upperBound) / 2)
            Spacer(minLength: 0)
            axisText(range.lowerBound)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }

    private func axisText(_ value: Double) -> some View {
        Text(String(format: "%.0f", value))
            .font(.system(size: 8, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 3)
            .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 3))
    }

    /// Four evenly spaced dates across the window, outer two flush to the edges.
    private var xTicks: [Date] {
        let lower = series.window.lowerBound
        let span = series.window.upperBound.timeIntervalSince(lower)
        return (0..<4).map { lower.addingTimeInterval(span * Double($0) / 3) }
    }

    private var xAxisLabels: some View {
        HStack(spacing: 0) {
            ForEach(Array(xTicks.enumerated()), id: \.offset) { index, date in
                Text(date.formatted(.dateTime.day().month(.abbreviated)))
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity,
                           alignment: index == 0 ? .leading
                                    : index == 3 ? .trailing : .center)
            }
        }
    }

    // MARK: hover

    private func nearestPoint(toX pointerX: CGFloat, width: CGFloat) -> TrendPoint? {
        guard width > 0 else { return nil }
        let span = series.window.upperBound.timeIntervalSince(series.window.lowerBound)
        let fraction = max(0, min(1, Double(pointerX / width)))
        let target = series.window.lowerBound.addingTimeInterval(span * fraction)
        return series.allPoints.min {
            abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target))
        }
    }

    private func readout(for point: TrendPoint) -> some View {
        let stamp = point.date.formatted(.dateTime.day().month(.abbreviated).hour().minute())
        let value = String(format: "%.0f", point.value)
        return Text(series.unit.isEmpty ? "\(stamp) · \(value)" : "\(stamp) · \(value) \(series.unit)")
            .font(.system(size: 9, design: .rounded))
            .monospacedDigit()
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .padding(4)
    }

    // MARK: geometry

    private func x(for date: Date, in rect: CGRect) -> CGFloat {
        let span = series.window.upperBound.timeIntervalSince(series.window.lowerBound)
        guard span > 0 else { return rect.midX }
        let t = date.timeIntervalSince(series.window.lowerBound) / span
        return rect.minX + rect.width * max(0, min(1, t))
    }

    private func y(for value: Double, in rect: CGRect) -> CGFloat {
        let range = bounds
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return rect.midY }
        let t = (value - range.lowerBound) / span
        return rect.maxY - rect.height * max(0, min(1, t))
    }

    // MARK: drawing

    /// Normal / elevated / high / severe as faint horizontal bands, so a value
    /// can be read qualitatively without consulting the axis.
    private func drawSeverityBands(_ ctx: inout GraphicsContext, in rect: CGRect) {
        let cuts: [(ClosedRange<Double>, DrynessLevel)] = [
            (0...25, .normal), (25...50, .elevated), (50...75, .high), (75...100, .severe),
        ]
        for (range, level) in cuts {
            let top = y(for: range.upperBound, in: rect)
            let bottom = y(for: range.lowerBound, in: rect)
            let band = CGRect(x: rect.minX, y: top, width: rect.width, height: bottom - top)
            ctx.fill(Path(band), with: .color(level.color.opacity(0.08)))
        }
    }

    private func drawGridLines(_ ctx: inout GraphicsContext, in rect: CGRect) {
        let range = bounds
        for fraction in [0.0, 0.5, 1.0] {
            let value = range.lowerBound + (range.upperBound - range.lowerBound) * fraction
            let lineY = y(for: value, in: rect)
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: lineY))
            path.addLine(to: CGPoint(x: rect.maxX, y: lineY))
            ctx.stroke(path, with: .color(.secondary.opacity(0.12)), lineWidth: 0.5)
        }
    }

    private func drawCrosshair(_ point: TrendPoint,
                               _ ctx: inout GraphicsContext,
                               in rect: CGRect) {
        let px = x(for: point.date, in: rect)
        let py = y(for: point.value, in: rect)

        var line = Path()
        line.move(to: CGPoint(x: px, y: rect.minY))
        line.addLine(to: CGPoint(x: px, y: rect.maxY))
        ctx.stroke(line, with: .color(.secondary.opacity(0.35)),
                   style: StrokeStyle(lineWidth: 0.75, dash: [2, 2]))

        let dot = CGRect(x: px - 3, y: py - 3, width: 6, height: 6)
        ctx.fill(Path(ellipseIn: dot), with: .color(.white))
        ctx.stroke(Path(ellipseIn: dot), with: .color(.secondary), lineWidth: 1)
    }

    private func drawSegment(_ segment: TrendSegment,
                             _ ctx: inout GraphicsContext,
                             in rect: CGRect) {
        let points = segment.points.map {
            CGPoint(x: x(for: $0.date, in: rect), y: y(for: $0.value, in: rect))
        }
        guard let first = points.first else { return }

        // A lone point would draw nothing as a path, so mark it as a dot.
        guard points.count > 1 else {
            let dot = CGRect(x: first.x - 2, y: first.y - 2, width: 4, height: 4)
            ctx.fill(Path(ellipseIn: dot), with: .color(tint(for: segment)))
            return
        }

        var line = Path()
        line.move(to: first)
        for point in points.dropFirst() { line.addLine(to: point) }

        var area = line
        area.addLine(to: CGPoint(x: points[points.count - 1].x, y: rect.maxY))
        area.addLine(to: CGPoint(x: first.x, y: rect.maxY))
        area.closeSubpath()

        let color = tint(for: segment)
        ctx.fill(area, with: .linearGradient(
            Gradient(colors: [color.opacity(0.28), color.opacity(0.02)]),
            startPoint: CGPoint(x: 0, y: rect.minY),
            endPoint: CGPoint(x: 0, y: rect.maxY)))
        ctx.stroke(line, with: .color(color),
                   style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
    }

    /// Index segments take their color from the mean value on the hydro ramp;
    /// gauge segments have no 0–100 meaning, so they use the app's calm tone.
    private func tint(for segment: TrendSegment) -> Color {
        guard showsSeverityBands, !segment.points.isEmpty else { return Hydro.rampColor(20) }
        let mean = segment.points.reduce(0) { $0 + $1.value } / Double(segment.points.count)
        return Hydro.rampColor(mean)
    }
}

#Preview {
    let end = Date()
    let start = end.addingTimeInterval(-30 * 86_400)
    let points = (0..<300).map { i -> TrendPoint in
        let t = Double(i) / 300
        return TrendPoint(date: start.addingTimeInterval(t * 30 * 86_400),
                          value: 40 + sin(t * 6) * 18 + t * 12)
    }
    return TrendChart(
        series: .make(from: points, window: start...end, gapThreshold: 21_600,
                      maxPoints: 31, yScale: .fixed(0...100), unit: ""),
        showsSeverityBands: true)
        .frame(width: 284, height: 120)
        .padding()
}
