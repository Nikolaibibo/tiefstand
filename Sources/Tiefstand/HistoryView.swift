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

    enum Window: String, CaseIterable, Identifiable {
        case week, month
        var id: String { rawValue }
        var label: String { self == .week ? "7 d" : "30 d" }
        var days: Int { self == .week ? 7 : 30 }
        /// 160 points for a week; 31 for a month, which is one bucket per day.
        var maxPoints: Int { self == .week ? 160 : 31 }
    }

    /// 3× the 2 h poll interval — anything longer is a real recording gap.
    static let indexGapThreshold: TimeInterval = 21_600
    /// 12× PEGELONLINE's 15-minute cadence; their occasional dropouts should
    /// read as dropouts.
    static let gaugeGapThreshold: TimeInterval = 10_800

    /// Gauge first: it has 30 days of real data on the very first open, while
    /// the index has only what this Mac has recorded so far.
    @Published var series: Series = .gauge
    @Published var window: Window = .month
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

    var indexSeries: TrendSeries {
        let points = historyStore.load().map { TrendPoint(date: $0.timestamp, value: $0.index) }
        return .make(from: points,
                     window: range(forDays: window.days),
                     gapThreshold: Self.indexGapThreshold,
                     maxPoints: window.maxPoints,
                     yScale: .fixed(0...100),
                     unit: "")
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

    /// A lone dot on an empty month reads as a rendering glitch rather than as
    /// data, so the index tab shows its explanation until there are at least
    /// two points to draw a line between.
    var indexIsTooSparseToPlot: Bool { indexSeries.allPoints.count < 2 }

    /// "Recording since 3 Aug · 12 of 30 days", or the gauge's provenance.
    var caption: String {
        switch series {
        case .index:
            let samples = historyStore.load()
            guard let first = samples.first else { return "No samples recorded yet" }
            let covered = Int((indexSeries.coverage * Double(window.days)).rounded())
            let since = first.timestamp.formatted(
                .dateTime.day().month(.abbreviated).locale(Self.uiLocale))
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
                message("Recording started today — the curve appears after the next update")
            } else if model.currentSeries.isEmpty {
                message("No readings for this window")
            } else {
                TrendChart(series: model.currentSeries,
                           showsSeverityBands: model.series == .index)
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
        HStack(spacing: 6) {
            ForEach(HistoryModel.Window.allCases) { option in
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
