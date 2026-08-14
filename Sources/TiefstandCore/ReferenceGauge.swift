import Foundation

/// The gauge whose water level the history view plots.
///
/// **Why a fixed gauge and not the station in the popover.** NIWIS and
/// PEGELONLINE share no identifiers, so the obvious design was to match the
/// app's `localStation` to a nearby gauge by coordinate. Measured against the
/// live lists on 2026-08-15, that fails: PEGELONLINE covers federal waterways
/// only, and 80 % of the twenty driest NIWIS stations — precisely the ones the
/// app shows — have no federal gauge within 25 km. The tab would have been
/// empty most of the time.
///
/// Kaub on the Rhine is Germany's canonical low-water bellwether, the gauge
/// quoted whenever Rhine shipping makes the news, and it carries a complete
/// 30-day series. It guarantees a real curve on the very first open without
/// a location permission or a matching heuristic.
///
/// `GaugeMatcher` remains in the package for the CoreLocation roadmap item,
/// where matching *is* the right tool: a user's nearest gauge, not a national
/// extreme, is usually on a federal waterway.
public enum ReferenceGauge {

    /// PEGELONLINE `shortname`. Resolved against the station list rather than
    /// hardcoded by UUID, so a re-issued identifier doesn't silently break the
    /// tab.
    public static let shortname = "KAUB"

    /// Observed 2026-08-15. Used only if the name lookup fails.
    public static let fallbackUUID = "1d26e504-7f9e-480a-b52c-5932be6549ab"

    /// Finds the reference gauge in a station list, by name first and by the
    /// recorded UUID second.
    public static func resolve(in stations: [GaugeStation]) -> GaugeStation? {
        stations.first { $0.shortname.uppercased() == shortname }
            ?? stations.first { $0.uuid == fallbackUUID }
    }
}
