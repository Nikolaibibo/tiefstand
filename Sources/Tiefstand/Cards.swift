import SwiftUI
import AppKit
import TiefstandCore
import TiefstandUI

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
        .help("\(title) severity 0–100, averaged across stations. Dots: station count per class — normal · low · very low · extremely low.")
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
    /// Set when the station was picked by proximity; `nil` means it is the
    /// driest gauge in the country instead.
    var distance: String?
    @State private var hovering = false

    var body: some View {
        Button { openExternally(niwisURL) } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill((station.lowWaterClass.map(Hydro.classColor) ?? .gray).opacity(0.18))
                        .frame(width: 34, height: 34)
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(station.lowWaterClass.map(Hydro.classColor) ?? .gray)
                }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(station.name).font(.subheadline).fontWeight(.medium).lineLimit(1)
                        Image(systemName: "arrow.up.forward")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.tertiary)
                            .opacity(hovering ? 1 : 0.35)
                    }
                    Text(distance ?? "Driest discharge gauge")
                        .font(.caption2).foregroundStyle(.tertiary)
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
            .background(.quaternary.opacity(hovering ? 0.6 : 0.4), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.06)))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hovering = inside
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .help(distance == nil
              ? "\(station.name) — the driest discharge gauge right now. Click to open the NIWIS map."
              : "\(station.name) — your nearest discharge gauge. Click to open the NIWIS map.")
    }
}
