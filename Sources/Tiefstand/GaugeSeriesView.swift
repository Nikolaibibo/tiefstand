import SwiftUI
import TiefstandCore
import TiefstandUI

/// One gauge's own record, opened by clicking its dot on the map.
///
/// This is the polite use of the NIWIS timeseries endpoint: a single request
/// for the single station someone actually asked about, rather than the 644 it
/// would take to rebuild the national picture.
@MainActor
final class GaugeSeriesModel: ObservableObject {

    @Published var window: TrendWindow = .year
    @Published private(set) var isLoading = false
    @Published private(set) var errorText: String?
    @Published private(set) var series: StationSeries?

    private let provider: NIWISProvider
    private struct CacheKey: Hashable { let station: String; let days: Int }
    private var cache: [CacheKey: StationSeries] = [:]

    init(provider: NIWISProvider = NIWISProvider()) {
        self.provider = provider
    }

    func load(station: StationReading, domain: WaterDomain) async {
        let key = CacheKey(station: station.id, days: window.days)
        if let cached = cache[key] {
            series = cached
            return
        }

        isLoading = true
        errorText = nil
        defer { isLoading = false }

        do {
            let fetched = try await provider.stationSeries(
                domain: domain, stationNumber: station.id, days: window.days)
            cache[key] = fetched
            series = fetched
        } catch {
            errorText = error.localizedDescription
        }
    }

    /// The measured curve. Auto-scaled: cubic metres per second and metres of
    /// groundwater have no shared bounds with anything.
    func trendSeries(days: Int) -> TrendSeries {
        let end = Date()
        let window = end.addingTimeInterval(-Double(days) * 86_400)...end
        return .make(from: series?.values ?? [],
                     window: window,
                     // Daily values: a gap of more than three days is a gap.
                     gapThreshold: 3 * 86_400,
                     maxPoints: self.window.maxPoints,
                     yScale: .auto,
                     unit: series?.unit ?? "")
    }

    /// The three class boundaries as overlays on the same axis.
    ///
    /// NIWIS does not publish these thresholds; `diagrammErgebnis` returns them
    /// as one daily curve per class. Drawn behind the measurement, you can
    /// watch the river cross into "extremely low" rather than be told it did.
    func thresholdOverlays(days: Int) -> [TrendOverlay] {
        guard let series else { return [] }
        let end = Date()
        let window = end.addingTimeInterval(-Double(days) * 86_400)...end
        let tints: [String: Color] = [
            "Low": Hydro.classColor(.low),
            "Very low": Hydro.classColor(.veryLow),
            "Extremely low": Hydro.classColor(.extremelyLow),
        ]
        return series.thresholds.map { threshold in
            TrendOverlay(
                id: threshold.label,
                series: .make(from: threshold.points, window: window,
                              gapThreshold: 3 * 86_400,
                              maxPoints: self.window.maxPoints,
                              yScale: .auto, unit: series.unit),
                label: threshold.label,
                color: tints[threshold.label] ?? .secondary)
        }
    }
}

struct GaugeSeriesView: View {
    @ObservedObject var model: GaugeSeriesModel
    let station: StationReading
    let domain: WaterDomain
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            chart
            windowPicker
        }
        .task(id: "\(station.id)-\(model.window.rawValue)") {
            await model.load(station: station, domain: domain)
        }
        .background {
            Button("", action: onBack)
                .keyboardShortcut(.escape, modifiers: [])
                .opacity(0).frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Image(systemName: "chevron.left").font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .help("Back")

            VStack(alignment: .leading, spacing: 0) {
                Text(station.name)
                    .font(.subheadline).fontWeight(.medium).lineLimit(1)
                Text(domain == .discharge ? "Discharge" : "Groundwater")
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
            }
            Spacer()
            if model.isLoading { ProgressView().controlSize(.small) }
        }
    }

    @ViewBuilder
    private var chart: some View {
        let series = model.trendSeries(days: model.window.days)
        ZStack {
            if series.isEmpty && !model.isLoading {
                Text(model.errorText ?? "No record for this window")
                    .font(.caption).foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center).padding(.horizontal, 12)
            } else {
                TrendChart(series: series,
                           showsSeverityBands: false,
                           overlays: model.thresholdOverlays(days: model.window.days),
                           // The measurand, not the unit: "m³/s" beside "Low"
                           // and "Very low" labels a legend entry with a scale.
                           legendLabel: model.thresholdOverlays(days: model.window.days).isEmpty
                                        ? nil : (domain == .discharge ? "Discharge" : "Groundwater"))
            }
        }
        .frame(height: 142)

        Text(caption)
            .font(.caption2)
            .foregroundStyle(model.errorText == nil ? Color.secondary : Color.red)
            .lineLimit(2)
    }

    private var caption: String {
        if let error = model.errorText { return error }
        guard let series = model.series else { return "" }
        var parts: [String] = []
        if let days = station.daysBelowThreshold, days > 0 {
            parts.append("\(days) d below threshold")
        }
        if let reference = series.referencePeriod {
            parts.append("class boundaries vs \(reference)")
        }
        return parts.joined(separator: " · ")
    }

    private var windowPicker: some View {
        HStack(spacing: 8) {
            ForEach(TrendWindow.stationSeries, id: \.rawValue) { option in
                Button(option.label) { model.window = option }
                    .buttonStyle(.borderless)
                    .font(.caption2.weight(model.window == option ? .bold : .regular))
                    .foregroundStyle(model.window == option ? Color.primary : Color.secondary)
            }
            Spacer()
        }
    }
}
