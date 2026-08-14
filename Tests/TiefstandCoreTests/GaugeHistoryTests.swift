import XCTest
@testable import TiefstandCore

final class GaugeHistoryTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tiefstand-gauge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: decoding

    /// Shape of `stations.json`, verified live 2026-08-14.
    func test_decodesTheStationList() throws {
        let json = Data("""
        [
          {"uuid":"b475386c-30cc-453a-b3b7-1d17ace13595","number":"48300105",
           "shortname":"CELLE","longname":"CELLE","km":1.74,"agency":"VERDEN",
           "longitude":10.062164,"latitude":52.622706,
           "water":{"shortname":"ALLER","longname":"ALLER"}},
          {"uuid":"no-coords","number":"1","shortname":"X","longname":"X",
           "water":{"shortname":"Y","longname":"Y"}}
        ]
        """.utf8)

        let stations = try PEGELONLINEHistoryProvider.decodeStations(json)

        XCTAssertEqual(stations.count, 2)
        XCTAssertEqual(stations[0].uuid, "b475386c-30cc-453a-b3b7-1d17ace13595")
        XCTAssertEqual(stations[0].shortname, "CELLE")
        XCTAssertEqual(stations[0].water?.shortname, "ALLER")
        XCTAssertEqual(stations[0].latitude ?? 0, 52.622706, accuracy: 0.000001)
        XCTAssertNil(stations[1].latitude)
    }

    /// Shape of `stations/{uuid}/W/measurements.json`, verified live 2026-08-14.
    func test_decodesMeasurementsIncludingTheUTCOffset() throws {
        let json = Data("""
        [
          {"timestamp":"2026-07-15T15:45:00+02:00","value":135.0},
          {"timestamp":"2026-08-14T15:30:00+02:00","value":114.0}
        ]
        """.utf8)

        let measurements = try PEGELONLINEHistoryProvider.decodeMeasurements(json)

        XCTAssertEqual(measurements.count, 2)
        XCTAssertEqual(measurements[0].value, 135.0)
        // 15:45+02:00 is 13:45 UTC.
        let expected = DateComponents(calendar: Calendar(identifier: .gregorian),
                                      timeZone: TimeZone(secondsFromGMT: 0),
                                      year: 2026, month: 7, day: 15,
                                      hour: 13, minute: 45).date!
        XCTAssertEqual(measurements[0].timestamp, expected)
    }

    func test_measurementsMapToTrendPoints() throws {
        let json = Data("""
        [{"timestamp":"2026-08-14T15:30:00+02:00","value":114.0}]
        """.utf8)

        let points = try PEGELONLINEHistoryProvider.decodeMeasurements(json).map(\.trendPoint)

        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].value, 114.0)
    }

    // MARK: URL construction

    func test_measurementURLRequestsTheWaterLevelSeriesForTheGivenWindow() {
        let provider = PEGELONLINEHistoryProvider()

        let url = provider.measurementsURL(uuid: "abc", days: 7)

        XCTAssertEqual(url.absoluteString,
            "https://www.pegelonline.wsv.de/webservices/rest-api/v2/stations/abc/W/measurements.json?start=P7D")
    }

    func test_measurementURLEscapesTheIdentifier() {
        let provider = PEGELONLINEHistoryProvider()

        let url = provider.measurementsURL(uuid: "a b", days: 30)

        XCTAssertTrue(url.absoluteString.contains("a%20b"))
        XCTAssertTrue(url.absoluteString.hasSuffix("start=P30D"))
    }

    // MARK: station cache

    func test_stationCacheReturnsWhatItStored() throws {
        let cache = GaugeStationCache(fileURL: directory.appendingPathComponent("s.json"),
                                      maxAge: 30 * 86_400)
        let now = Date()
        let stations = try PEGELONLINEHistoryProvider.decodeStations(Data("""
        [{"uuid":"u","number":"1","shortname":"S","longname":"S",
          "longitude":10.0,"latitude":52.0,"water":{"shortname":"W","longname":"W"}}]
        """.utf8))

        try cache.write(stations, now: now)

        XCTAssertEqual(cache.read(now: now.addingTimeInterval(86_400))?.count, 1)
    }

    func test_stationCacheExpires() throws {
        let cache = GaugeStationCache(fileURL: directory.appendingPathComponent("s.json"),
                                      maxAge: 30 * 86_400)
        let now = Date()
        try cache.write([], now: now)

        XCTAssertNil(cache.read(now: now.addingTimeInterval(31 * 86_400)))
    }

    func test_stationCacheReturnsNilWhenAbsent() {
        let cache = GaugeStationCache(fileURL: directory.appendingPathComponent("missing.json"),
                                      maxAge: 30 * 86_400)

        XCTAssertNil(cache.read(now: Date()))
    }
}
