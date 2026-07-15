import Foundation

/// The four NIWIS domains. Raw values are the API's `PARAM` path segments.
public enum WaterDomain: String, CaseIterable {
    case discharge = "ABFLUSS"
    case waterLevel = "WASSERSTAND"
    case groundwater = "GRUNDWASSER"
    case springFlow = "QUELLSCHUETTUNG"
}

public enum DataProviderError: Error, Equatable {
    case noData
}

/// A source of low-water data. NIWIS is primary; PEGELONLINE is the planned fallback.
public protocol DataProvider {
    func aggregate(for domain: WaterDomain) async throws -> DomainAggregate
    func stations(for domain: WaterDomain) async throws -> [StationReading]
}

public extension DataProvider {
    /// The headline metric: discharge + groundwater aggregates fetched
    /// concurrently, combined 50/50.
    func currentDrynessIndex() async throws -> DrynessIndex {
        async let discharge = aggregate(for: .discharge)
        async let groundwater = aggregate(for: .groundwater)
        guard let index = DrynessIndex.combined(discharge: try await discharge,
                                                groundwater: try await groundwater) else {
            throw DataProviderError.noData
        }
        return index
    }
}
