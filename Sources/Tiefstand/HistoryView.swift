import SwiftUI
import TiefstandCore
import TiefstandUI

/// Owns the history screen's state: which series, which window, the fetched
/// gauge curve and its cache.
///
/// Gauge history is fetched **only** in response to a user action — opening
/// the screen or switching tab/window. The README promises the app polls at
/// most every two hours, and that stays true only as long as nothing here
/// runs on a timer.
@MainActor
final class HistoryModel: ObservableObject {

    enum Series: String, CaseIterable, Identifiable {
        case gauge, index
        var id: String { rawValue }
        var label: String { self == .gauge ? "Gauge" : "Index" }
    }

    /// Windows the current tab can honestly show. The gauge is capped at a
    /// month because PEGELONLINE serves no more (see `TrendWindow`).
    var availableWindows: [TrendWindow] {
        series == .index ? TrendWindow.index : TrendWindow.gauge
    }

    /// 3× the 2 h poll interval — anything longer is a real recording gap.
    static let indexGapThreshold: TimeInterval = 21_600
    /// 12× PEGELONLINE's 15-minute cadence; their occasional dropouts should
    /// read as dropouts.
    static let gaugeGapThreshold: TimeInterval = 10_800

    /// Gauge first: it has 30 days of real data on the very first open, while
    /// the index has only what this Mac has recorded so far.
    @Published var series: Series = .gauge {
        didSet {
            // Leaving a 12-month index view for the gauge must not ask
            // PEGELONLINE for a year — it would answer with a month and look
            // like it worked.
            let clamped = window.clamped(to: availableWindows)
            if clamped != window { window = clamped }
        }
    }
    @Published var window: TrendWindow = .month
    @Published private(set) var isLoading = false
    @Published private(set) var errorText: String?
    @Published private(set) var gauge: GaugeStation?
    @Published private(set) var gaugeUnavailable = false

    private let historyStore: IndexHistoryStoring
    private let gauges: GaugeHistoryProviding

    private struct CacheKey: Hashable { let uuid: String; let days: Int }
    private var measurementCache: [CacheKey: (fetchedAt: Date, points: [TrendPoint])] = [:]
    private var gaugePoints: [TrendPoint] = []
    private static let cacheLifetime: TimeInterval = 3_600

    init(historyStore: IndexHistoryStoring = IndexHistoryStore(),
         gauges: GaugeHistoryProviding = PEGELONLINEHistoryProvider()) {
        self.historyStore = historyStore
        self.gauges = gauges
    }

    // MARK: series

    /// Named `range(forDays:)` rather than `window(...)` on purpose — `window`
    /// is already the published property, and overloading the name here reads
    /// as ambiguous at every call site.
    private func range(forDays days: Int) -> ClosedRange<Date> {
        let end = Date()
        return end.addingTimeInterval(-Double(days) * 86_400)...end
    }

    func series(for metric: DrynessMetric) -> TrendSeries {
        .make(from: historyStore.load().points(for: metric),
              window: range(forDays: window.days),
              gapThreshold: Self.indexGapThreshold,
              maxPoints: window.maxPoints,
              yScale: .fixed(0...100),
              unit: "")
    }

    var indexSeries: TrendSeries { series(for: .index) }

    /// Discharge and groundwater under the index, on the same 0–100 axis.
    ///
    /// The headline number is the mean of these two, so on its own it hides
    /// which compartment is driving it. The donuts show that split for right
    /// now; these curves show whether the gap between surface and sub-surface
    /// water is widening or closing.
    var domainOverlays: [TrendOverlay] {
        [DrynessMetric.discharge, .groundwater].compactMap { metric in
            guard let color = Hydro.overlayTint(metric) else { return nil }
            let series = series(for: metric)
            guard !series.isEmpty else { return nil }
            return TrendOverlay(id: metric.rawValue, series: series,
                                label: metric.label, color: color)
        }
    }

    var gaugeSeries: TrendSeries {
        .make(from: gaugePoints,
              window: range(forDays: window.days),
              gapThreshold: Self.gaugeGapThreshold,
              maxPoints: window.maxPoints,
              yScale: .auto,
              unit: "cm")
    }

    var currentSeries: TrendSeries { series == .index ? indexSeries : gaugeSeries }

    var title: String { series == .index ? "Dryness Index" : "Water level" }

    /// The whole UI is English, so dates are too — `.formatted` otherwise
    /// follows the system language and renders "15. Aug." next to "Recording
    /// since".
    private static let uiLocale = Locale(identifier: "en_US")

    /// Whether there is too little recorded time to draw anything meaningful.
    ///
    /// Counting *points* was the wrong test: 32 samples recorded over 65
    /// minutes pass a "more than one point" check and then render as an
    /// invisible smudge against the right-hand edge of a 7-day axis. What
    /// matters is how much of the window they span, so the guard is coverage:
    /// under 2 % — a couple of hours on a week, half a day on a month — the
    /// explanation is more use than the curve.
    var indexIsTooSparseToPlot: Bool {
        indexSeries.allPoints.count < 2 || indexSeries.coverage < 0.02
    }

    /// Says how long the app has actually been recording, rather than the flat
    /// "started today" — after a day of running, "started today" would be a
    /// lie and the user would still see no curve.
    var sparseExplanation: String {
        let samples = historyStore.load()
        guard let first = samples.first, let last = samples.last else {
            return "Nothing recorded yet — the first sample lands on the next refresh"
        }
        let minutes = Int(last.timestamp.timeIntervalSince(first.timestamp) / 60)
        let span = minutes < 90
            ? "\(max(minutes, 1)) min"
            : "\(minutes / 60) h"
        return "Only \(span) recorded so far — NIWIS publishes no back history, "
             + "so this curve has to be built up as the app runs"
    }

    /// "Recording since 3 Aug · 12 of 30 days", or the gauge's provenance.
    var caption: String {
        switch series {
        case .index:
            let samples = historyStore.load()
            guard let first = samples.first else { return "No samples recorded yet" }
            let covered = Int((indexSeries.coverage * Double(window.days)).rounded())
            // Include the year once the record reaches back into another one,
            // or "Aug 15" reads as today rather than as a year ago.
            let calendar = Calendar.current
            var style = Date.FormatStyle.dateTime.day().month(.abbreviated)
            if calendar.component(.year, from: first.timestamp)
                != calendar.component(.year, from: Date()) {
                style = style.year()
            }
            let since = first.timestamp.formatted(style.locale(Self.uiLocale))
            return "Recording since \(since) · \(covered) of \(window.days) days"
        case .gauge:
            guard let gauge else { return "" }
            return "\(gauge.displayName) · national reference gauge"
        }
    }

    // MARK: loading

    /// Called when the screen appears and whenever tab or window changes.
    func load() async {
        guard series == .gauge else { return }   // the index comes off disk

        isLoading = true
        errorText = nil
        defer { isLoading = false }

        do {
            let station: GaugeStation
            if let gauge {
                station = gauge
            } else {
                guard let resolved = ReferenceGauge.resolve(in: try await gauges.stations()) else {
                    gaugeUnavailable = true
                    gaugePoints = []
                    return
                }
                station = resolved
                gauge = resolved
            }
            gaugeUnavailable = false

            let key = CacheKey(uuid: station.uuid, days: window.days)
            if let cached = measurementCache[key],
               Date().timeIntervalSince(cached.fetchedAt) < Self.cacheLifetime {
                gaugePoints = cached.points
                return
            }

            let points = try await gauges
                .measurements(uuid: station.uuid, days: window.days)
                .map(\.trendPoint)
            measurementCache[key] = (Date(), points)
            gaugePoints = points
        } catch {
            // Keep whatever curve is already on screen; only say what failed.
            errorText = error.localizedDescription
        }
    }
}

/// The history screen. Replaces the popover's contents in place, same 320 pt
/// width, fixed height so opening it doesn't make the popover jump.
struct HistoryView: View {
    @ObservedObject var model: HistoryModel
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            chart
            windowPicker
            seriesPicker
        }
        .task(id: taskKey) { await model.load() }
        // Esc goes back, matching the chevron. `.keyboardShortcut` needs a
        // focusable control, so the shortcut rides on a zero-size hidden button
        // rather than on the view itself.
        .background {
            Button("", action: onBack)
                .keyboardShortcut(.escape, modifiers: [])
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }

    /// Re-runs the load whenever the tab or window changes — and only then.
    private var taskKey: String { "\(model.series.rawValue)-\(model.window.rawValue)" }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Image(systemName: "chevron.left").font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .help("Back")

            Text(model.title)
                .font(.subheadline).fontWeight(.medium)
            Spacer()
            if model.isLoading { ProgressView().controlSize(.small) }
        }
    }

    @ViewBuilder
    private var chart: some View {
        ZStack {
            if model.series == .gauge && model.gaugeUnavailable {
                message("Reference gauge unavailable")
            } else if model.series == .index && model.indexIsTooSparseToPlot {
                message(model.sparseExplanation)
            } else if model.currentSeries.isEmpty {
                message("No readings for this window")
            } else if model.series == .index {
                TrendChart(series: model.currentSeries,
                           showsSeverityBands: true,
                           overlays: model.domainOverlays,
                           legendLabel: model.domainOverlays.isEmpty ? nil : "Index")
            } else {
                TrendChart(series: model.currentSeries, showsSeverityBands: false)
            }
        }
        .frame(height: 132)

        Text(model.errorText ?? model.caption)
            .font(.caption2)
            .foregroundStyle(model.errorText == nil ? Color.secondary : Color.red)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
    }

    private var windowPicker: some View {
        HStack(spacing: 8) {
            ForEach(model.availableWindows, id: \.rawValue) { option in
                Button(option.label) { model.window = option }
                    .buttonStyle(.borderless)
                    .font(.caption2.weight(model.window == option ? .bold : .regular))
                    .foregroundStyle(model.window == option ? Color.primary : Color.secondary)
            }
            Spacer()
        }
    }

    private var seriesPicker: some View {
        Picker("", selection: $model.series) {
            ForEach(HistoryModel.Series.allCases) { option in
                Text(option.label).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}
