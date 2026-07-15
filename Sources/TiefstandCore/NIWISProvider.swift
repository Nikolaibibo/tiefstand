import Foundation

/// Primary `DataProvider` backed by the NIWIS public API (no auth).
/// Endpoints reverse-engineered on the 2026-07-15 launch day:
///   GET /kreisdiagramme/{PARAM}                              → DomainAggregate
///   GET /karte/messstelle/{PARAM}?klassifikationsart=DYNAMISCH → [StationReading]
public struct NIWISProvider: DataProvider {
    public let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL = URL(string: "https://niwis-online.de/api")!,
                session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func aggregate(for domain: WaterDomain) async throws -> DomainAggregate {
        let url = baseURL
            .appendingPathComponent("kreisdiagramme")
            .appendingPathComponent(domain.rawValue)
        let (data, _) = try await session.data(from: url)
        return try JSONDecoder().decode(DomainAggregate.self, from: data)
    }

    public func stations(for domain: WaterDomain) async throws -> [StationReading] {
        let path = baseURL
            .appendingPathComponent("karte")
            .appendingPathComponent("messstelle")
            .appendingPathComponent(domain.rawValue)
        var components = URLComponents(url: path, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "klassifikationsart", value: "DYNAMISCH")]
        let (data, _) = try await session.data(from: components.url!)
        return try JSONDecoder().decode([StationReading].self, from: data)
    }
}
