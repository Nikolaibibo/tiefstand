import Foundation

/// One gauge's record: the measured series plus the low-water class boundaries
/// that NIWIS classifies it against.
///
/// The boundaries are the interesting part. NIWIS classifies each station by
/// percentile thresholds against the 1991–2020 WMO reference period and does
/// not publish the numbers — but `diagrammErgebnis` returns them as one curve
/// per class, day by day, in the same unit as the measurement. Drawn together,
/// you can watch a river cross into "extremely low" instead of being told that
/// it did.
public struct StationSeries: Equatable, Sendable {

    public struct Threshold: Equatable, Sendable {
        public let label: String
        public let points: [TrendPoint]
    }

    public let stationName: String
    public let unit: String
    public let values: [TrendPoint]
    /// Ordered mildest to most severe, matching how they are drawn.
    public let thresholds: [Threshold]
    public let referencePeriod: String?

    public init(stationName: String, unit: String, values: [TrendPoint],
                thresholds: [Threshold], referencePeriod: String?) {
        self.stationName = stationName
        self.unit = unit
        self.values = values
        self.thresholds = thresholds
        self.referencePeriod = referencePeriod
    }
}

extension StationSeries {

    /// German class labels as NIWIS spells them, in severity order, mapped to
    /// the English the rest of the app uses.
    private static let classLabels: [(source: String, display: String)] = [
        ("niedrig", "Low"),
        ("sehr niedrig", "Very low"),
        ("extrem niedrig", "Extremely low"),
    ]

    private struct DTO: Decodable {
        struct Series: Decodable {
            struct Value: Decodable { let messwert: Double?; let datum: String }
            let einheit: String?
            let werte: [Value]
        }
        struct Area: Decodable {
            struct Span: Decodable { let datum: String; let obererWert: Double? }
            let label: String?
            let spannen: [Span]
        }
        struct Reference: Decodable { let von: String?; let bis: String? }

        let ueberschrift: String?
        let zeitreihen: [Series]
        let flaechen: [Area]
        let referenzzeitraum: Reference?
    }

    /// Dates arrive as `2025-08-15` on the series and `2025-08-15T00:00:00` on
    /// the boundary spans — same day, two spellings — so both are read as a day
    /// in Berlin time, which is the calendar NIWIS publishes against.
    private static func day(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Berlin")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: String(text.prefix(10)))
    }

    public static func decode(_ data: Data) throws -> StationSeries {
        let dto = try JSONDecoder().decode(DTO.self, from: data)

        // A null reading is a hole in the record, not a river at zero flow.
        let values: [TrendPoint] = (dto.zeitreihen.first?.werte ?? []).compactMap { value in
            guard let measurement = value.messwert, let date = day(value.datum) else { return nil }
            return TrendPoint(date: date, value: measurement)
        }

        let thresholds: [Threshold] = classLabels.compactMap { mapping in
            guard let area = dto.flaechen.first(where: {
                $0.label?.lowercased() == mapping.source
            }) else { return nil }
            let points: [TrendPoint] = area.spannen.compactMap { span in
                guard let bound = span.obererWert, let date = day(span.datum) else { return nil }
                return TrendPoint(date: date, value: bound)
            }
            return points.isEmpty ? nil : Threshold(label: mapping.display, points: points)
        }

        var reference: String?
        if let from = dto.referenzzeitraum?.von?.prefix(4),
           let to = dto.referenzzeitraum?.bis?.prefix(4) {
            reference = "\(from)–\(to)"
        }

        return StationSeries(stationName: dto.ueberschrift ?? "",
                             unit: dto.zeitreihen.first?.einheit ?? "",
                             values: values,
                             thresholds: thresholds,
                             referencePeriod: reference)
    }
}

public extension NIWISProvider {

    /// `GET /api/infodiagramm/diagrammErgebnis` — one gauge's daily record.
    ///
    /// Reverse-engineered from the portal on 2026-08-15; the endpoint is not
    /// in any published spec. It is strict: leave out any one of these
    /// parameters and it answers 400 naming the one it wants, which is how the
    /// shape was found. Daily values reach back to 1991.
    func stationSeriesURL(domain: WaterDomain,
                          stationNumber: String,
                          from: String,
                          to: String) -> URL {
        let path = baseURL
            .appendingPathComponent("infodiagramm")
            .appendingPathComponent("diagrammErgebnis")
        var components = URLComponents(url: path, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "messgroesse", value: domain.rawValue),
            URLQueryItem(name: "diagrammart", value: "ZEITREIHE"),
            URLQueryItem(name: "messstelleNr", value: stationNumber),
            URLQueryItem(name: "klassifikationsAnzeige", value: "DYNAMISCH"),
            URLQueryItem(name: "von", value: from),
            URLQueryItem(name: "bis", value: to),
        ]
        return components.url!
    }

    /// One gauge's daily record over the given window, with its class
    /// boundaries. Fetched only when someone asks for a specific gauge — one
    /// request for the one station they pointed at.
    func stationSeries(domain: WaterDomain,
                       stationNumber: String,
                       days: Int,
                       now: Date = Date()) async throws -> StationSeries {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Berlin")
        formatter.dateFormat = "yyyy-MM-dd"

        let url = stationSeriesURL(
            domain: domain,
            stationNumber: stationNumber,
            from: formatter.string(from: now.addingTimeInterval(-Double(days) * 86_400)),
            to: formatter.string(from: now))

        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        return try StationSeries.decode(data)
    }
}

public extension TrendWindow {
    /// A gauge's own record is daily and reaches back to 1991, so a week would
    /// be seven points and is not offered.
    static let stationSeries: [TrendWindow] = [.month, .quarter, .halfYear, .year]
}
