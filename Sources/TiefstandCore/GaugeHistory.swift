import Foundation

/// One PEGELONLINE gauge from `stations.json`.
///
/// Coordinates are optional: a handful of entries ship without them, and a
/// station we can't place simply can't be matched (see `GaugeMatcher`).
public struct GaugeStation: Codable, Equatable, Sendable {
    public let uuid: String
    public let shortname: String
    public let longname: String
    public let longitude: Double?
    public let latitude: Double?
    public let water: Water?

    public struct Water: Codable, Equatable, Sendable {
        public let shortname: String
        public let longname: String

        public init(shortname: String, longname: String) {
            self.shortname = shortname
            self.longname = longname
        }
    }

    public init(uuid: String, shortname: String, longname: String,
                longitude: Double?, latitude: Double?, water: Water?) {
        self.uuid = uuid
        self.shortname = shortname
        self.longname = longname
        self.longitude = longitude
        self.latitude = latitude
        self.water = water
    }

    /// "CELLE · ALLER", or just the name when the water body is unknown.
    public var displayName: String {
        guard let water = water?.shortname, !water.isEmpty else { return shortname }
        return "\(shortname) · \(water)"
    }
}

/// One water-level reading.
public struct GaugeMeasurement: Decodable, Equatable, Sendable {
    public let timestamp: Date
    public let value: Double

    public init(timestamp: Date, value: Double) {
        self.timestamp = timestamp
        self.value = value
    }

    public var trendPoint: TrendPoint { TrendPoint(date: timestamp, value: value) }
}

public protocol GaugeHistoryProviding {
    func stations() async throws -> [GaugeStation]
    func measurements(uuid: String, days: Int) async throws -> [GaugeMeasurement]
}

/// Reads gauge history from PEGELONLINE (WSV), the documented, stable source
/// that NIWIS lacks an equivalent for. It keeps a rolling 30-day window, which
/// is the hard ceiling on this series.
public struct PEGELONLINEHistoryProvider: GaugeHistoryProviding {

    public static let defaultBaseURL =
        URL(string: "https://www.pegelonline.wsv.de/webservices/rest-api/v2")!

    public let baseURL: URL
    private let session: URLSession
    private let stationCache: GaugeStationCache

    public init(baseURL: URL = PEGELONLINEHistoryProvider.defaultBaseURL,
                session: URLSession = .shared,
                stationCache: GaugeStationCache = .default) {
        self.baseURL = baseURL
        self.session = session
        self.stationCache = stationCache
    }

    // MARK: URLs

    func stationsURL() -> URL {
        baseURL.appendingPathComponent("stations.json")
    }

    /// `stations/{uuid}/W/measurements.json?start=P{days}D`. `W` is water level
    /// — the only series PEGELONLINE offers for every gauge.
    func measurementsURL(uuid: String, days: Int) -> URL {
        let path = baseURL
            .appendingPathComponent("stations")
            .appendingPathComponent(uuid)
            .appendingPathComponent("W")
            .appendingPathComponent("measurements.json")
        var components = URLComponents(url: path, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "start", value: "P\(days)D")]
        return components.url!
    }

    private func request(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(NIWISProvider.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    // MARK: Decoding

    static func decodeStations(_ data: Data) throws -> [GaugeStation] {
        try JSONDecoder().decode([GaugeStation].self, from: data)
    }

    static func decodeMeasurements(_ data: Data) throws -> [GaugeMeasurement] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601   // handles the "+02:00" offset
        return try decoder.decode([GaugeMeasurement].self, from: data)
    }

    // MARK: Fetching

    /// The gauge list is ~262 KB and effectively static, so it is cached on
    /// disk for 30 days. A stale-cache read beats re-downloading it per click.
    public func stations() async throws -> [GaugeStation] {
        if let cached = stationCache.read(now: Date()) { return cached }
        let (data, _) = try await session.data(for: request(for: stationsURL()))
        let stations = try Self.decodeStations(data)
        try? stationCache.write(stations, now: Date())
        return stations
    }

    public func measurements(uuid: String, days: Int) async throws -> [GaugeMeasurement] {
        let (data, _) = try await session.data(for: request(for: measurementsURL(uuid: uuid, days: days)))
        return try Self.decodeMeasurements(data)
    }
}

/// On-disk cache for the gauge list, with an explicit clock so it is testable
/// without waiting 30 days.
public struct GaugeStationCache {

    private struct Envelope: Codable {
        let storedAt: Date
        let stations: [GaugeStation]
    }

    public let fileURL: URL
    public let maxAge: TimeInterval

    public init(fileURL: URL, maxAge: TimeInterval) {
        self.fileURL = fileURL
        self.maxAge = maxAge
    }

    public static var `default`: GaugeStationCache {
        let base = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return GaugeStationCache(
            fileURL: base
                .appendingPathComponent("Tiefstand", isDirectory: true)
                .appendingPathComponent("pegelonline-stations.json"),
            maxAge: 30 * 86_400)
    }

    /// `nil` when absent, unreadable or older than `maxAge` — every one of
    /// which simply means "fetch it again".
    public func read(now: Date) -> [GaugeStation]? {
        guard let data = try? Data(contentsOf: fileURL),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              now.timeIntervalSince(envelope.storedAt) <= maxAge
        else { return nil }
        return envelope.stations
    }

    public func write(_ stations: [GaugeStation], now: Date) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Envelope(storedAt: now, stations: stations))
        try data.write(to: fileURL, options: .atomic)
    }
}
