import SwiftUI
import AppKit
import ServiceManagement
import TiefstandCore
import TiefstandUI

/// The NIWIS national low-water map — where the popover links out to.
let niwisURL = URL(string: "https://niwis-online.de")!

func openExternally(_ url: URL) { NSWorkspace.shared.open(url) }

/// Launch-at-login via the modern ServiceManagement API (macOS 13+).
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Tiefstand: login-item toggle failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Popover

struct PopoverView: View {
    @ObservedObject var model: IndexModel
    @StateObject private var history = HistoryModel()
    @StateObject private var gaugeSeries = GaugeSeriesModel()
    @State private var launchAtLogin = LoginItem.isEnabled
    /// Three screens, not two booleans: a second flag would allow states that
    /// cannot exist ("history and a gauge at once") and the compiler could not
    /// stop us reaching them.
    @State private var screen: Screen = .dashboard
    @State private var headerHovering = false
    @State private var mapDomain: WaterDomain = .discharge
    @State private var hoveredStation: StationReading?

    private var level: DrynessLevel? { model.index.map { DrynessLevel(index: $0.value) } }

    enum Screen: Equatable {
        case dashboard
        case history
        case gauge(StationReading, WaterDomain)
    }

    var body: some View {
        Group {
            switch screen {
            case .dashboard:
                dashboard
            case .history:
                HistoryView(model: history, onBack: { screen = .dashboard })
            case .gauge(let station, let domain):
                GaugeSeriesView(model: gaugeSeries, station: station, domain: domain,
                                onBack: { screen = .dashboard })
            }
        }
        .padding(18)
        .background(background)
        .animation(.easeInOut(duration: 0.18), value: screen)
    }

    private var dashboard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button { screen = .history } label: { header }
                .buttonStyle(.plain)
                .background(.quaternary.opacity(headerHovering ? 0.4 : 0),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onHover { inside in
                    headerHovering = inside
                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            if let d = model.discharge, let g = model.groundwater {
                categorySection(discharge: d, groundwater: g)
            } else if model.isLoading {
                loading
            }
            if !mapStations.isEmpty {
                regionSection
            }
            if let station = model.localStation {
                LocalStationCard(station: station, distance: model.localStationDistance)
            }
            footer
        }
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
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .opacity(headerHovering ? 1 : 0)
            }
        }
        .help("National Dryness Index (0–100): the mean of the discharge and groundwater severity scores. Higher means drier. Click for the 7- and 30-day trend.")
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

    /// Which domain the map is showing. Discharge by default: it has the
    /// denser network (357 gauges against 287) and comes back with the same
    /// request the app already made.
    private var mapStations: [StationReading] {
        mapDomain == .discharge ? model.dischargeStations : model.groundwaterStations
    }

    private var regionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("BY REGION")
                    .font(.system(size: 10, weight: .semibold)).tracking(0.8)
                    .foregroundStyle(.tertiary)
                    // On the heading, not the section: on the map itself the
                    // tooltip drops over the gauges a second into exploring
                    // them, hiding exactly what you are pointing at.
                    .help("Every NIWIS gauge in the country, coloured by its low-water class — normal · low · very low · extremely low. The national index is the average of these; the map is the spread behind it. Point at a gauge for its reading.")
                Spacer()
                Picker("", selection: $mapDomain) {
                    Text("Discharge").tag(WaterDomain.discharge)
                    Text("Groundwater").tag(WaterDomain.groundwater)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.mini)
                .fixedSize()
            }

            // Sized by height, not width: at 284 pt across, a portrait Germany
            // would be ~380 pt tall and swamp the popover.
            HStack(alignment: .top, spacing: 14) {
                StationMap(stations: mapStations, hovered: $hoveredStation,
                           onSelect: { screen = .gauge($0, mapDomain) })
                    .frame(height: 186)
                // The detail replaces the legend in place, so pointing at a
                // gauge doesn't shift the layout under the cursor.
                Group {
                    if let hoveredStation {
                        StationDetail(station: hoveredStation)
                    } else {
                        StationMapLegend(stations: mapStations)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 186)
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
            .help("Refresh now")

            Menu {
                Button("Refresh") { Task { await model.refresh() } }
                Button("View on NIWIS…") { openExternally(niwisURL) }
                if model.canOfferLocation {
                    Button("Use My Location…") { model.requestLocation() }
                }
                Divider()
                Toggle("Launch at Login", isOn: $launchAtLogin)
                Divider()
                Button("Quit Tiefstand") { NSApplication.shared.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle").font(.caption)
            }
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
            .onChange(of: launchAtLogin) { LoginItem.set(launchAtLogin) }
        }
    }
}
