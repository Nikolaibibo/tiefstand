import SwiftUI
import TiefstandCore

// MARK: - Menu bar

struct MenuBarLabel: View {
    let index: Double?
    var body: some View {
        HStack(spacing: 3) {
            WaveGlyph(fill: (index ?? 0) / 100,
                      color: index.map(Hydro.rampColor) ?? .secondary)
                .frame(width: 13, height: 13)
            Text(index.map { "\(Int($0.rounded()))" } ?? "–")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }
}

/// A circular gauge filled from the bottom with a small sine surface — the app's motif.
struct WaveGlyph: View {
    var fill: Double
    var color: Color

    var body: some View {
        Canvas { ctx, size in
            let circle = Path(ellipseIn: CGRect(origin: .zero, size: size))
            ctx.stroke(circle, with: .color(color.opacity(0.4)), lineWidth: 1)
            ctx.clip(to: circle)

            let f = max(0, min(1, fill))
            let level = size.height * (1 - f)
            let amp = size.height * 0.06
            var wave = Path()
            wave.move(to: CGPoint(x: 0, y: level))
            let steps = 16
            for i in 0...steps {
                let x = size.width * Double(i) / Double(steps)
                let y = level + sin(Double(i) / Double(steps) * .pi * 2) * amp
                wave.addLine(to: CGPoint(x: x, y: y))
            }
            wave.addLine(to: CGPoint(x: size.width, y: size.height))
            wave.addLine(to: CGPoint(x: 0, y: size.height))
            wave.closeSubpath()
            ctx.fill(wave, with: .color(color))
        }
    }
}

// MARK: - Popover

struct PopoverView: View {
    @ObservedObject var model: IndexModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let d = model.discharge, let g = model.groundwater {
                HStack(alignment: .top, spacing: 24) {
                    DonutView(title: "Discharge", aggregate: d)
                    DonutView(title: "Groundwater", aggregate: g)
                    Spacer()
                }
            } else if model.isLoading {
                ProgressView().controlSize(.small)
            }

            if let station = model.localStation {
                Divider()
                LocalStationRow(station: station)
            }

            Divider()
            footer
        }
        .padding(16)
        .task { await model.refresh() }
    }

    private var header: some View {
        let value = model.index?.value
        let level = value.map(DrynessLevel.init(index:))
        return HStack(spacing: 12) {
            WaveGlyph(fill: (value ?? 0) / 100,
                      color: value.map(Hydro.rampColor) ?? .secondary)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(value.map { "\(Int($0.rounded()))" } ?? "–")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(level?.color ?? .primary)
                Text(level?.label ?? "Loading…")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text("Dryness Index").font(.caption).foregroundStyle(.secondary)
                Text("Germany").font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(model.errorText ?? "Source: NIWIS · BfG")
                .font(.caption2)
                .foregroundStyle(model.errorText == nil ? Color.secondary : Color.red)
            Spacer()
            if let t = model.updatedAt {
                Text(t.formatted(date: .omitted, time: .shortened))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Button {
                Task { await model.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
        }
    }
}

/// A 4-segment ring showing a domain's class distribution, score in the center.
struct DonutView: View {
    let title: String
    let aggregate: DomainAggregate

    var body: some View {
        VStack(spacing: 6) {
            Canvas { ctx, size in
                let total = Double(aggregate.classifiedCount)
                guard total > 0 else { return }
                let segments: [(Int, LowWaterClass)] = [
                    (aggregate.keinNiedrigwasser, .none),
                    (aggregate.niedrig, .low),
                    (aggregate.sehrNiedrig, .veryLow),
                    (aggregate.extremNiedrig, .extremelyLow),
                ]
                let lineWidth = min(size.width, size.height) * 0.16
                let radius = (min(size.width, size.height) - lineWidth) / 2
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                var startDeg = -90.0
                for (count, cls) in segments where count > 0 {
                    let endDeg = startDeg + 360 * Double(count) / total
                    var arc = Path()
                    arc.addArc(center: center, radius: radius,
                               startAngle: .degrees(startDeg), endAngle: .degrees(endDeg),
                               clockwise: false)
                    ctx.stroke(arc, with: .color(Hydro.classColor(cls)),
                               style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    startDeg = endDeg
                }
            }
            .frame(width: 68, height: 68)
            .overlay(
                Text(aggregate.severityScore.map { "\(Int($0.rounded()))" } ?? "–")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
            )
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct LocalStationRow: View {
    let station: StationReading

    var body: some View {
        HStack(spacing: 10) {
            if let cls = station.lowWaterClass {
                Circle().fill(Hydro.classColor(cls)).frame(width: 10, height: 10)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(station.name).font(.subheadline).lineLimit(1)
                Text("Driest discharge gauge").font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            if let trend = station.trend {
                Image(systemName: trend.symbolName).font(.caption).foregroundStyle(.secondary)
            }
            if let value = station.currentValue {
                Text(String(format: "%.1f", value))
                    .font(.system(.subheadline, design: .rounded)).monospacedDigit()
            }
        }
    }
}
