import SwiftUI
import AppKit
import TiefstandCore

// MARK: - Menu bar

struct MenuBarLabel: View {
    let index: Double?
    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: Self.glyphImage(for: index))
            Text(index.map { "\(Int($0.rounded()))" } ?? "–")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }

    /// The menu bar renders `Canvas`/`Shape` content in a `MenuBarExtra` label as
    /// blank, so we rasterize the glyph to a retina NSImage up front. `isTemplate
    /// = false` keeps the hydro colors instead of a monochrome mask.
    @MainActor
    static func glyphImage(for index: Double?) -> NSImage {
        let side: CGFloat = 15
        let renderer = ImageRenderer(content:
            MenuBarGlyph(index: index).frame(width: side, height: side))
        renderer.scale = 2
        guard let image = renderer.nsImage else {
            return NSImage(size: NSSize(width: side, height: side))
        }
        image.isTemplate = false
        return image
    }
}

/// A water-in-a-vessel disc tuned for the menu bar: a soft empty vessel, a vivid
/// wave-fill whose height tracks the index, a crisp rim, and a white surface
/// glint. Built from plain SwiftUI `Shape`s (not `Canvas`, which doesn't render
/// inside a `MenuBarExtra` label) and rasterized by `MenuBarLabel`, so it stays
/// legible and reads as a level — not a flat disc — at ~15pt over any wallpaper.
struct MenuBarGlyph: View {
    let index: Double?

    var body: some View {
        let tint = Hydro.rampColor(index ?? 0)
        let disc = Circle().inset(by: 1)
        ZStack {
            // soft empty vessel: the disc is always a filled shape, so the water
            // level reads against a container rather than the bare wallpaper.
            disc.fill(tint.opacity(0.16))

            if let index {
                let f = max(0.06, min(1, index / 100))
                WaveFillShape(fraction: f)
                    .fill(LinearGradient(
                        colors: [Hydro.rampColor(max(0, index - 18)), tint],
                        startPoint: .top, endPoint: .bottom))
                    .clipShape(disc)
                WaveSurfaceLine(fraction: f)
                    .stroke(.white.opacity(0.65), lineWidth: 0.8)
                    .clipShape(disc)
            }

            disc.stroke(tint.opacity(0.9), lineWidth: 1.2)
        }
    }
}

/// The sine surface line for a fill at `fraction` of the height.
private func waveSurface(in rect: CGRect, fraction: Double) -> (points: [CGPoint], level: CGFloat) {
    let level = rect.height * (1 - fraction)
    let amp = rect.height * 0.06
    let steps = 24
    let pts = (0...steps).map { i -> CGPoint in
        let x = rect.minX + rect.width * Double(i) / Double(steps)
        let y = level + sin(Double(i) / Double(steps) * .pi * 2) * amp
        return CGPoint(x: x, y: y)
    }
    return (pts, level)
}

/// Water filled from the bottom to `fraction` of the height, capped by a ripple.
struct WaveFillShape: Shape {
    var fraction: Double
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let (pts, _) = waveSurface(in: rect, fraction: fraction)
        p.addLines(pts)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Just the water surface line (for a glint highlight).
struct WaveSurfaceLine: Shape {
    var fraction: Double
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addLines(waveSurface(in: rect, fraction: fraction).points)
        return p
    }
}

// MARK: - Wave gauge (the motif)

/// Circular gauge filled from the bottom with a gently moving sine surface.
struct WaveGauge: View {
    var fraction: Double      // 0…1 fill height
    var index: Double         // drives color
    var animated: Bool = true

    var body: some View {
        if animated {
            TimelineView(.animation) { timeline in
                canvas(phase: timeline.date.timeIntervalSinceReferenceDate)
            }
        } else {
            canvas(phase: 0)
        }
    }

    private func canvas(phase: Double) -> some View {
        Canvas { ctx, size in
            let bounds = CGRect(origin: .zero, size: size)
            let ring = Path(ellipseIn: bounds.insetBy(dx: 0.5, dy: 0.5))

            // faint track
            ctx.stroke(ring, with: .color(Hydro.rampColor(index).opacity(0.25)),
                       lineWidth: max(1, size.width * 0.05))
            ctx.clip(to: ring)

            let f = max(0, min(1, fraction))
            let level = size.height * (1 - f)
            let amp = size.height * 0.05
            let wave = wavePath(in: size, level: level, amp: amp, phase: phase)

            ctx.fill(wave, with: .linearGradient(
                Gradient(colors: [Hydro.rampColor(max(0, index - 22)), Hydro.rampColor(index)]),
                startPoint: CGPoint(x: 0, y: level - amp),
                endPoint: CGPoint(x: 0, y: size.height)))

            // subtle surface highlight
            ctx.stroke(surfaceLine(in: size, level: level, amp: amp, phase: phase),
                       with: .color(.white.opacity(0.5)), lineWidth: 0.75)
        }
    }

    private func wavePath(in size: CGSize, level: CGFloat, amp: CGFloat, phase: Double) -> Path {
        var p = surfaceLine(in: size, level: level, amp: amp, phase: phase)
        p.addLine(to: CGPoint(x: size.width, y: size.height))
        p.addLine(to: CGPoint(x: 0, y: size.height))
        p.closeSubpath()
        return p
    }

    private func surfaceLine(in size: CGSize, level: CGFloat, amp: CGFloat, phase: Double) -> Path {
        var p = Path()
        let steps = 28
        for i in 0...steps {
            let x = size.width * Double(i) / Double(steps)
            let y = level + sin(Double(i) / Double(steps) * .pi * 2 + phase * 1.6) * amp
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
            else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        return p
    }
}

// MARK: - Popover

struct PopoverView: View {
    @ObservedObject var model: IndexModel

    private var level: DrynessLevel? { model.index.map { DrynessLevel(index: $0.value) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if let d = model.discharge, let g = model.groundwater {
                categorySection(discharge: d, groundwater: g)
            } else if model.isLoading {
                loading
            }
            if let station = model.localStation {
                LocalStationCard(station: station)
            }
            footer
        }
        .padding(18)
        .background(background)
        .task { await model.refresh() }
    }

    private var background: some View {
        let tint = level?.color ?? .clear
        return ZStack {
            Rectangle().fill(.ultraThinMaterial)
            LinearGradient(colors: [tint.opacity(0.18), .clear],
                           startPoint: .top, endPoint: .center)
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        let value = model.index?.value
        return HStack(spacing: 14) {
            WaveGauge(fraction: (value ?? 0) / 100, index: value ?? 0)
                .frame(width: 62, height: 62)
                .shadow(color: (level?.color ?? .clear).opacity(0.35), radius: 8, y: 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(value.map { "\(Int($0.rounded()))" } ?? "–")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Hydro.gradient(value ?? 0))
                    .contentTransition(.numericText())
                if let level {
                    Text(level.label.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(0.8)
                        .foregroundStyle(level.color)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(level.color.opacity(0.16), in: Capsule())
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Image(systemName: "drop.fill").foregroundStyle(Hydro.rampColor(value ?? 0))
                Text("Dryness").font(.caption2).foregroundStyle(.secondary)
                Text("Germany").font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private func categorySection(discharge d: DomainAggregate, groundwater g: DomainAggregate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BY CATEGORY")
                .font(.system(size: 10, weight: .semibold)).tracking(0.8)
                .foregroundStyle(.tertiary)
            HStack(spacing: 12) {
                DomainCard(title: "Discharge", systemImage: "water.waves", aggregate: d)
                DomainCard(title: "Groundwater", systemImage: "arrow.down.to.line", aggregate: g)
            }
        }
    }

    private var loading: some View {
        HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
            .frame(height: 90)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: model.errorText == nil ? "checkmark.seal" : "exclamationmark.triangle")
                .font(.caption2)
                .foregroundStyle(model.errorText == nil ? Color.secondary : Color.red)
            Text(model.errorText ?? "NIWIS · Bundesanstalt für Gewässerkunde")
                .font(.caption2)
                .foregroundStyle(model.errorText == nil ? Color.secondary : Color.red)
                .lineLimit(1)
            Spacer()
            if let t = model.updatedAt {
                Text(t.formatted(date: .omitted, time: .shortened))
                    .font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
            }
            Button { Task { await model.refresh() } } label: {
                Image(systemName: "arrow.clockwise").font(.caption)
            }
            .buttonStyle(.borderless)
            .disabled(model.isLoading)
        }
    }
}

// MARK: - Domain donut card

struct DomainCard: View {
    let title: String
    let systemImage: String
    let aggregate: DomainAggregate

    private var segments: [(count: Int, cls: LowWaterClass)] {
        [(aggregate.keinNiedrigwasser, .none), (aggregate.niedrig, .low),
         (aggregate.sehrNiedrig, .veryLow), (aggregate.extremNiedrig, .extremelyLow)]
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                Image(systemName: systemImage).font(.caption2)
                Text(title).font(.caption).fontWeight(.medium)
            }
            .foregroundStyle(.secondary)

            ZStack {
                Donut(segments: segments)
                    .frame(width: 78, height: 78)
                VStack(spacing: 0) {
                    Text(aggregate.severityScore.map { "\(Int($0.rounded()))" } ?? "–")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("/100").font(.system(size: 8)).foregroundStyle(.tertiary)
                }
            }

            HStack(spacing: 7) {
                ForEach(segments, id: \.cls) { seg in
                    HStack(spacing: 2) {
                        Circle().fill(Hydro.classColor(seg.cls)).frame(width: 5, height: 5)
                        Text("\(seg.count)").font(.system(size: 8, design: .rounded))
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(.white.opacity(0.06)))
    }
}

/// Four-segment ring with a small gap between segments and rounded caps.
struct Donut: View {
    let segments: [(count: Int, cls: LowWaterClass)]

    var body: some View {
        Canvas { ctx, size in
            let total = Double(segments.reduce(0) { $0 + $1.count })
            guard total > 0 else { return }
            let lineWidth = min(size.width, size.height) * 0.17
            let radius = (min(size.width, size.height) - lineWidth) / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let gap = 3.0
            var startDeg = -90.0
            for seg in segments where seg.count > 0 {
                let full = 360 * Double(seg.count) / total
                let endDeg = startDeg + max(0, full - gap)
                var arc = Path()
                arc.addArc(center: center, radius: radius,
                           startAngle: .degrees(startDeg), endAngle: .degrees(endDeg),
                           clockwise: false)
                let c = Hydro.classColor(seg.cls)
                ctx.stroke(arc, with: .linearGradient(
                    Gradient(colors: [c.opacity(0.7), c]),
                    startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                startDeg += full
            }
        }
    }
}

// MARK: - Local station

struct LocalStationCard: View {
    let station: StationReading

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill((station.lowWaterClass.map(Hydro.classColor) ?? .gray).opacity(0.18))
                    .frame(width: 34, height: 34)
                Image(systemName: "mappin.circle.fill")
                    .foregroundStyle(station.lowWaterClass.map(Hydro.classColor) ?? .gray)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(station.name).font(.subheadline).fontWeight(.medium).lineLimit(1)
                Text("Driest discharge gauge").font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            if let trend = station.trend {
                Image(systemName: trend.symbolName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .background(.quaternary.opacity(0.5), in: Circle())
            }
            if let value = station.currentValue {
                Text(String(format: "%.0f", value))
                    .font(.system(.title3, design: .rounded)).fontWeight(.semibold)
                    .monospacedDigit()
                + Text(" cm").font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(.white.opacity(0.06)))
    }
}
