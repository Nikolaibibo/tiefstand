import SwiftUI
import AppKit
import TiefstandCore

@main
struct TiefstandApp: App {
    @StateObject private var model = IndexModel()

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
                .frame(width: 320)
        } label: {
            MenuBarLabel(index: model.index?.value)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Loads the national index + a local station from NIWIS and publishes it.
@MainActor
final class IndexModel: ObservableObject {
    @Published var index: DrynessIndex?
    @Published var discharge: DomainAggregate?
    @Published var groundwater: DomainAggregate?
    @Published var localStation: StationReading?
    /// Every gauge, for the map. These arrays were already being fetched and
    /// discarded — only the driest station survived the refresh.
    @Published var dischargeStations: [StationReading] = []
    @Published var groundwaterStations: [StationReading] = []
    @Published var isLoading = false
    @Published var errorText: String?
    @Published var updatedAt: Date?

    private let provider: DataProvider
    private let history: IndexHistoryStoring
    private var autoRefreshTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?

    init(provider: DataProvider = NIWISProvider(),
         history: IndexHistoryStoring = IndexHistoryStore()) {
        self.provider = provider
        self.history = history
        startAutoRefreshing()
        observeWake()
    }

    deinit {
        autoRefreshTask?.cancel()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    /// Kicks off a fresh pull whenever the Mac wakes from sleep — otherwise the
    /// label could sit stale for up to a full poll interval after a lid-close.
    private func observeWake() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }

    /// Refreshes once immediately, then keeps polling in the background so the
    /// menu-bar label stays current without the popover ever being opened.
    func startAutoRefreshing(interval: Duration = .seconds(7200)) {
        guard autoRefreshTask == nil else { return }
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: interval)
            }
        }
    }

    func refresh() async {
        isLoading = true
        errorText = nil
        do {
            async let d = provider.aggregate(for: .discharge)
            async let g = provider.aggregate(for: .groundwater)
            // Station lists feed the map and the local-gauge card, but the
            // index is computed from the aggregates alone — so a failure here
            // must not take the whole refresh down with it. It used to: the
            // call was `try`, and a stumble on the map endpoint blanked the
            // number as well.
            async let ds = try? provider.stations(for: .discharge)
            async let gs = try? provider.stations(for: .groundwater)

            let (dd, gg) = try await (d, g)
            let (dischargeList, groundwaterList) = await (ds ?? [], gs ?? [])

            withAnimation(.easeInOut) {
                discharge = dd
                groundwater = gg
                index = DrynessIndex.combined(discharge: dd, groundwater: gg)
                dischargeStations = dischargeList
                groundwaterStations = groundwaterList
                // TODO: nearest via CoreLocation; for now the driest station stands in.
                localStation = dischargeList.max { lhs, rhs in
                    (lhs.lowWaterClass?.severityIndex ?? -1) < (rhs.lowWaterClass?.severityIndex ?? -1)
                } ?? localStation
                updatedAt = Date()
            }

            // The only place index history is ever created. A failed write must
            // never surface as a refresh error: a missing sample is a gap in a
            // chart, not a broken app.
            if let index {
                try? history.append(DrynessSample(index: index, timestamp: updatedAt ?? Date()))
            }
        } catch {
            errorText = error.localizedDescription
        }
        isLoading = false
    }
}
