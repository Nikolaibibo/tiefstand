import WidgetKit
import SwiftUI
import TiefstandCore
import TiefstandUI

/// The desktop widget: the national Dryness Index as the signature wave gauge
/// plus the number and its level. Supports small and medium families.
struct DrynessWidget: Widget {
    let kind = "TiefstandDrynessWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DrynessProvider()) { entry in
            DrynessWidgetView(entry: entry)
        }
        .configurationDisplayName("Tiefstand")
        .description("Germany's nationwide low-water Dryness Index at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct DrynessWidgetView: View {
    let entry: DrynessEntry
    @Environment(\.widgetFamily) private var family

    private var level: DrynessLevel? { entry.index.map { DrynessLevel(index: $0) } }
    private var tint: Color { Hydro.rampColor(entry.index ?? 0) }

    var body: some View {
        Group {
            if family == .systemMedium {
                HStack(spacing: 18) {
                    gauge(side: 84)
                    readout
                    Spacer(minLength: 0)
                }
            } else {
                VStack(spacing: 8) {
                    gauge(side: 66)
                    readout
                }
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(colors: [tint.opacity(0.22), tint.opacity(0.05)],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    private func gauge(side: CGFloat) -> some View {
        // Static render — WidgetKit snapshots don't run continuous animation.
        WaveGauge(fraction: (entry.index ?? 0) / 100, index: entry.index ?? 0, animated: false)
            .frame(width: side, height: side)
    }

    private var readout: some View {
        VStack(alignment: family == .systemMedium ? .leading : .center, spacing: 2) {
            Text("Tiefstand")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            Text(entry.index.map { "\(Int($0.rounded()))" } ?? "–")
                .font(.system(size: family == .systemMedium ? 44 : 30,
                              weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(level?.label ?? "Keine Daten")
                .font(.caption.weight(.semibold))
                .foregroundStyle(level?.color ?? .secondary)
            if family == .systemMedium {
                Text("Niedrigwasser Deutschland")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
