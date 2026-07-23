import Foundation

/// Primary `DataProvider` backed by the NIWIS public data API (open, no auth).
/// NIWIS ships an open API for reuse; an official OpenAPI spec wasn't published at
/// launch, so these endpoints were observed from the live portal on 2026-07-15:
///   GET /kreisdiagramme/{PARAM}                              → DomainAggregate
///   GET /karte/messstelle/{PARAM}?klassifikationsart=DYNAMISCH → [StationReading]
public struct NIWISProvider: DataProvider {
    /// Identifies the client so the BfG can attribute (and reach us about) the
    /// traffic instead of just seeing an anonymous default agent. Kept generic
    /// (no patch version) so it stays stable across releases.
    public static let userAgent = "Tiefstand/0.1 (+https://github.com/Nikolaibibo/tiefstand)"

    public let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL = URL(string: "https://niwis-online.de/api")!,
                session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    /// Wraps a URL in a `URLRequest` carrying our identifying User-Agent, so the
    /// header travels regardless of the (injectable) session's configuration.
    private func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    public func aggregate(for domain: WaterDomain) async throws -> DomainAggregate {
        let url = baseURL
            .appendingPathComponent("kreisdiagramme")
            .appendingPathComponent(domain.rawValue)
        let (data, _) = try await session.data(for: request(for: url))
        return try JSONDecoder().decode(DomainAggregate.self, from: data)
    }

    public func stations(for domain: WaterDomain) async throws -> [StationReading] {
        let path = baseURL
            .appendingPathComponent("karte")
            .appendingPathComponent("messstelle")
            .appendingPathComponent(domain.rawValue)
        var components = URLComponents(url: path, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "klassifikationsart", value: "DYNAMISCH")]
        let (data, _) = try await session.data(for: request(for: components.url!))
        return try JSONDecoder().decode([StationReading].self, from: data)
    }
}
