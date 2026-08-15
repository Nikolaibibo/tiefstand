import SwiftUI
import AppKit
import TiefstandCore

/// Every gauge in the country as a dot, coloured by its low-water class, over
/// a thin outline of the border.
///
/// The station data behind this view was already being fetched on every
/// refresh and thrown away; for discharge the map costs no extra request.
public struct StationMap: View {
    private let stations: [StationReading]
    @Binding private var hovered: StationReading?
    private let onSelect: (StationReading) -> Void

    public init(stations: [StationReading],
                hovered: Binding<StationReading?>,
                onSelect: @escaping (StationReading) -> Void = { _ in }) {
        self.stations = stations
        self._hovered = hovered
        self.onSelect = onSelect
    }

    /// How close the cursor has to get, in points, before a gauge is picked up.
    private static let hitRadius: CGFloat = 9

    public var body: some View {
        GeometryReader { geometry in
            Canvas { ctx, size in
                drawOutline(&ctx, in: size)
                for station in Self.drawOrder(stations) {
                    draw(station, &ctx, in: size)
                }
                if let hovered, let point = Self.position(of: hovered, in: size) {
                    drawHighlight(at: point, &ctx)
                }
            }
            .contentShape(Rectangle())
            // The hover already resolved which gauge is under the cursor, so
            // the click has nothing left to work out.
            .onTapGesture { if let hovered { onSelect(hovered) } }
            .onHover { inside in
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hovered = Self.station(near: location, in: geometry.size, among: stations)
                case .ended:
                    hovered = nil
                }
            }
        }
        .aspectRatio(MapProjection.aspectRatio, contentMode: .fit)
    }

    // MARK: geometry

    static func position(of station: StationReading, in size: CGSize) -> CGPoint? {
        guard let unit = MapProjection.normalized(station.coordinate) else { return nil }
        return CGPoint(x: unit.x * size.width, y: unit.y * size.height)
    }

    /// The nearest gauge within `hitRadius`, or `nil`.
    ///
    /// Ties go to the more severe reading: where a dry gauge and a normal one
    /// sit on top of each other, the dry one is what the map is drawing on top
    /// and therefore what the cursor appears to be pointing at.
    static func station(near location: CGPoint,
                        in size: CGSize,
                        among stations: [StationReading]) -> StationReading? {
        var best: (station: StationReading, distance: CGFloat)?
        for station in stations {
            guard let point = position(of: station, in: size) else { continue }
            let distance = hypot(point.x - location.x, point.y - location.y)
            guard distance <= hitRadius else { continue }

            if let current = best {
                let closerByMargin = distance < current.distance - 1
                let similarButWorse = abs(distance - current.distance) <= 1
                    && (station.lowWaterClass?.severityIndex ?? -1)
                        > (current.station.lowWaterClass?.severityIndex ?? -1)
                if closerByMargin || similarButWorse { best = (station, distance) }
            } else {
                best = (station, distance)
            }
        }
        return best?.station
    }

    /// Harmless first, extreme last.
    ///
    /// Order decides what the map says. Drawn in arrival order, the extremely
    /// low gauges disappear under the ordinary ones wherever they overlap, and
    /// the country looks far calmer than it is.
    static func drawOrder(_ stations: [StationReading]) -> [StationReading] {
        stations.sorted { lhs, rhs in
            (lhs.lowWaterClass?.severityIndex ?? -1) < (rhs.lowWaterClass?.severityIndex ?? -1)
        }
    }

    // MARK: drawing

    /// Public-domain Natural Earth geometry, baked into `TiefstandCore`.
    /// Drawn first, so the gauges sit on top of it.
    private func drawOutline(_ ctx: inout GraphicsContext, in size: CGSize) {
        for ring in GermanyOutline.coordinateRings {
            var path = Path()
            for (index, coordinate) in ring.enumerated() {
                let unit = MapProjection.projected(coordinate)
                let point = CGPoint(x: unit.x * size.width, y: unit.y * size.height)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
            // `.primary`, not `.white`. The popover follows the system
            // appearance, and a hardcoded white hairline is invisible on the
            // light material — the outline was there all along and simply
            // could not be seen in light mode.
            ctx.fill(path, with: .color(.primary.opacity(0.04)))
            ctx.stroke(path, with: .color(.primary.opacity(0.30)),
                       style: StrokeStyle(lineWidth: 0.6, lineJoin: .round))
        }
    }

    private func draw(_ station: StationReading,
                      _ ctx: inout GraphicsContext,
                      in size: CGSize) {
        guard let point = Self.position(of: station, in: size) else { return }
        let radius: CGFloat = station.lowWaterClass == nil ? 1.1 : 1.7
        let rect = CGRect(x: point.x - radius, y: point.y - radius,
                          width: radius * 2, height: radius * 2)
        let color = station.lowWaterClass.map(Hydro.classColor) ?? .secondary
        ctx.fill(Path(ellipseIn: rect),
                 with: .color(color.opacity(station.lowWaterClass == nil ? 0.3 : 0.95)))
    }

    private func drawHighlight(at point: CGPoint, _ ctx: inout GraphicsContext) {
        let ring = CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)
        ctx.stroke(Path(ellipseIn: ring), with: .color(.white), lineWidth: 1.2)
    }
}

/// Counts per class beside the map, in the same dot-and-number vocabulary the
/// domain donuts already use — but named, since a bare number next to a colour
/// only reads when four of them sit in a row under a donut.
///
/// Vertical because Germany is portrait: a full-width map would be ~380 pt
/// tall in a 320 pt popover, so the map is sized by height instead and the
/// legend fills the column that leaves free.
public struct StationMapLegend: View {
    private let stations: [StationReading]

    public init(stations: [StationReading]) {
        self.stations = stations
    }

    private static let names: [LowWaterClass: String] = [
        .none: "Normal", .low: "Low", .veryLow: "Very low", .extremelyLow: "Extremely low",
    ]

    private var counts: [(cls: LowWaterClass, count: Int)] {
        LowWaterClass.allCases.map { cls in
            (cls, stations.filter { $0.lowWaterClass == cls }.count)
        }
    }

    private var classified: Int { counts.reduce(0) { $0 + $1.count } }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(counts, id: \.cls) { item in
                HStack(spacing: 5) {
                    Circle().fill(Hydro.classColor(item.cls)).frame(width: 5, height: 5)
                    Text("\(item.count)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 22, alignment: .trailing)
                    Text(Self.names[item.cls] ?? "")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            }
            Divider().padding(.vertical, 1)
            Text("\(stations.count) gauges")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            if classified < stations.count {
                Text("\(stations.count - classified) no data")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// What the legend column shows while the cursor is over a gauge.
///
/// This is also where `daysBelowThreshold` finally surfaces — NIWIS has been
/// sending `anzahlTageUnterGlw` all along and nothing ever displayed it.
public struct StationDetail: View {
    private let station: StationReading

    public init(station: StationReading) {
        self.station = station
    }

    private var tint: Color { station.lowWaterClass.map(Hydro.classColor) ?? .secondary }

    private var className: String {
        switch station.lowWaterClass {
        case .none?:          return "Normal"
        case .low?:           return "Low"
        case .veryLow?:       return "Very low"
        case .extremelyLow?:  return "Extremely low"
        case nil:             return "No data"
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(station.name)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 4) {
                Circle().fill(tint).frame(width: 5, height: 5)
                Text(className).font(.system(size: 9)).foregroundStyle(.secondary)
            }

            if let value = station.currentValue {
                HStack(spacing: 3) {
                    Text(String(format: "%.0f", value))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("cm").font(.system(size: 9)).foregroundStyle(.secondary)
                    if let trend = station.trend {
                        Image(systemName: trend.symbolName)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let days = station.daysBelowThreshold, days > 0 {
                Text("\(days) d below threshold")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
