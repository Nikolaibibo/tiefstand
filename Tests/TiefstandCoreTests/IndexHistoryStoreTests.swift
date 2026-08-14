import XCTest
@testable import TiefstandCore

final class IndexHistoryStoreTests: XCTestCase {

    private var directory: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tiefstand-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("index-history.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func store(retention: TimeInterval = IndexHistoryStore.defaultRetention) -> IndexHistoryStore {
        IndexHistoryStore(fileURL: fileURL, retention: retention)
    }

    func test_sampleRoundTripsThroughJSON_includingNilDomainScores() throws {
        let sample = DrynessSample(timestamp: Date(timeIntervalSince1970: 1_786_000_000),
                                   index: 47.5, dischargeScore: 44.0, groundwaterScore: nil)

        let data = try JSONEncoder().encode(sample)
        let decoded = try JSONDecoder().decode(DrynessSample.self, from: data)

        XCTAssertEqual(decoded, sample)
        XCTAssertNil(decoded.groundwaterScore)
    }

    func test_sampleFromDrynessIndexCarriesBothDomainScores() {
        let index = DrynessIndex(value: 47, dischargeScore: 44, groundwaterScore: 50)
        let at = Date(timeIntervalSince1970: 1_786_000_000)

        let sample = DrynessSample(index: index, timestamp: at)

        XCTAssertEqual(sample.timestamp, at)
        XCTAssertEqual(sample.index, 47)
        XCTAssertEqual(sample.dischargeScore, 44)
        XCTAssertEqual(sample.groundwaterScore, 50)
    }

    func test_appendThenLoadReturnsTheSample() throws {
        let sample = DrynessSample(timestamp: Date(), index: 47,
                                   dischargeScore: 44, groundwaterScore: 50)

        try store().append(sample)

        XCTAssertEqual(store().load(), [sample])
    }

    func test_appendKeepsSamplesInChronologicalOrder() throws {
        let now = Date()
        let subject = store()

        try subject.append(DrynessSample(timestamp: now.addingTimeInterval(-3600), index: 40,
                                         dischargeScore: nil, groundwaterScore: nil))
        try subject.append(DrynessSample(timestamp: now, index: 47,
                                         dischargeScore: nil, groundwaterScore: nil))

        XCTAssertEqual(subject.load().map(\.index), [40, 47])
    }

    func test_appendPrunesSamplesOlderThanTheRetentionWindow() throws {
        let now = Date()
        let subject = store(retention: 86_400)  // one day
        let stale = DrynessSample(timestamp: now.addingTimeInterval(-2 * 86_400), index: 10,
                                  dischargeScore: nil, groundwaterScore: nil)
        let fresh = DrynessSample(timestamp: now, index: 47,
                                  dischargeScore: nil, groundwaterScore: nil)

        try subject.append(stale)
        try subject.append(fresh)

        XCTAssertEqual(subject.load(), [fresh])
    }

    func test_loadReturnsEmptyWhenTheFileDoesNotExist() {
        XCTAssertTrue(store().load().isEmpty)
    }

    func test_loadReturnsEmptyAndSetsAsideACorruptFileWithoutThrowing() throws {
        try Data("not json at all".utf8).write(to: fileURL)

        XCTAssertTrue(store().load().isEmpty)

        let corrupt = directory.appendingPathComponent("index-history.corrupt.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: corrupt.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func test_appendRecoversAfterACorruptFile() throws {
        try Data("not json at all".utf8).write(to: fileURL)
        let sample = DrynessSample(timestamp: Date(), index: 47,
                                   dischargeScore: nil, groundwaterScore: nil)

        try store().append(sample)

        XCTAssertEqual(store().load(), [sample])
    }
}
