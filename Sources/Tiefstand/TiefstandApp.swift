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
    /// How far away `localStation` is, when it was chosen by location rather
    /// than by being the driest in the country.
    @Published var localStationDistance: String?
    /// Every gauge, for the map. These arrays were already being fetched and
    /// discarded — only the driest station survived the refresh.
    @Published var dischargeStations: [StationReading] = []
    @Published var groundwaterStations: [StationReading] = []
    @Published var isLoading = false
    @Published var errorText: String?
    @Published var updatedAt: Date?

    private let provider: DataProvider
    private let history: IndexHistoryStoring
    private let location = LocationProvider()

    /// Whether the ••• menu should still offer to use the location.
    var canOfferLocation: Bool { !location.isAuthorized }

    /// From the ••• menu — the one place the prompt can actually appear.
    /// The card updates via `onFix`, not from here: the fix arrives well after
    /// this returns.
    func requestLocation() {
        location.requestPermission()
    }

    /// Swaps the local gauge for the nearest one, using the stations already
    /// fetched. Does nothing without a fix, which keeps the driest gauge in
    /// place for anyone who declines.
    func applyNearestStation() {
        guard let here = location.coordinate,
              let nearest = NearestStation.to(here, in: dischargeStations) else { return }
        withAnimation(.easeInOut) {
            localStation = nearest.station
            localStationDistance = nearest.distanceLabel
        }
    }
    private var autoRefreshTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?

    init(provider: DataProvider = NIWISProvider(),
         history: IndexHistoryStoring = IndexHistoryStore()) {
        self.provider = provider
        self.history = history
        // Re-pick the local gauge the moment a fix lands, without another
        // network round trip — the station list is already in hand.
        location.onFix = { [weak self] in self?.applyNearestStation() }
        location.resumeIfAuthorized()
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
                // Your nearest gauge when the system will say where you are,
                // otherwise the driest one in the country — which is what the
                // app showed for its first four releases and remains a
                // perfectly good answer.
                if let here = location.coordinate,
                   let nearest = NearestStation.to(here, in: dischargeList) {
                    localStation = nearest.station
                    localStationDistance = nearest.distanceLabel
                } else {
                    localStationDistance = nil
                    localStation = dischargeList.max { lhs, rhs in
                        (lhs.lowWaterClass?.severityIndex ?? -1) < (rhs.lowWaterClass?.severityIndex ?? -1)
                    } ?? localStation
                }
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
