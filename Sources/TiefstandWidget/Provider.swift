import WidgetKit
import TiefstandCore

/// One timeline snapshot: the national Dryness Index at a moment in time.
/// `index == nil` means the fetch failed and the widget shows a no-data state.
struct DrynessEntry: TimelineEntry {
    let date: Date
    let index: Double?
}

/// Feeds the widget. Reuses the same `DataProvider` + index math as the app, and
/// the shared `WidgetRefresh` policy for how often WidgetKit reloads the timeline.
struct DrynessProvider: TimelineProvider {
    private let dataProvider: DataProvider

    init(dataProvider: DataProvider = NIWISProvider()) {
        self.dataProvider = dataProvider
    }

    /// A representative value for the widget gallery / while data loads.
    func placeholder(in context: Context) -> DrynessEntry {
        DrynessEntry(date: Date(), index: 45)
    }

    func getSnapshot(in context: Context, completion: @escaping (DrynessEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        Task { completion(await fetchEntry()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DrynessEntry>) -> Void) {
        Task {
            let entry = await fetchEntry()
            let reload = WidgetRefresh.next(after: Date(), success: entry.index != nil)
            completion(Timeline(entries: [entry], policy: .after(reload)))
        }
    }

    private func fetchEntry() async -> DrynessEntry {
        do {
            async let d = dataProvider.aggregate(for: .discharge)
            async let g = dataProvider.aggregate(for: .groundwater)
            let (discharge, groundwater) = try await (d, g)
            let value = DrynessIndex.combined(discharge: discharge, groundwater: groundwater)?.value
            return DrynessEntry(date: Date(), index: value)
        } catch {
            return DrynessEntry(date: Date(), index: nil)
        }
    }
}
