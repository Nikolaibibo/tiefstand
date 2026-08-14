import Foundation

/// Durable storage for recorded index samples.
public protocol IndexHistoryStoring {
    func append(_ sample: DrynessSample) throws
    func load() -> [DrynessSample]
}

/// Append-only JSON log in Application Support.
///
/// Deliberately a plain file rather than SwiftData or SQLite: at twelve
/// samples a day the whole record is a few hundred kilobytes, and a file keeps
/// `TiefstandCore` Foundation-only and unit-testable without a host app.
public struct IndexHistoryStore: IndexHistoryStoring {

    /// 400 days. Only 7- and 30-day windows are displayed, but a discarded
    /// sample is unrecoverable — NIWIS cannot backfill it. Keeping a year-plus
    /// costs ~200 KB and means an annual view is simply possible later.
    public static let defaultRetention: TimeInterval = 400 * 86_400

    public let fileURL: URL
    public let retention: TimeInterval

    public init(fileURL: URL = IndexHistoryStore.defaultFileURL,
                retention: TimeInterval = IndexHistoryStore.defaultRetention) {
        self.fileURL = fileURL
        self.retention = retention
    }

    /// `~/Library/Application Support/Tiefstand/index-history.json`.
    /// The app is not sandboxed (ad-hoc signed, `LSUIElement`), so this path
    /// is usable directly.
    public static var defaultFileURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Tiefstand", isDirectory: true)
            .appendingPathComponent("index-history.json")
    }

    private var corruptFileURL: URL {
        fileURL.deletingLastPathComponent()
            .appendingPathComponent("index-history.corrupt.json")
    }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601   // readable if anyone opens the file
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// Never throws. A missing file is an empty history; an unreadable one is
    /// set aside and also reported as empty. A broken log must not be able to
    /// stop the app from starting or refreshing.
    public func load() -> [DrynessSample] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        guard let samples = try? Self.decoder.decode([DrynessSample].self, from: data) else {
            setAsideCorruptFile()
            return []
        }
        return samples
    }

    public func append(_ sample: DrynessSample) throws {
        var samples = load()
        samples.append(sample)
        samples.sort { $0.timestamp < $1.timestamp }

        let cutoff = sample.timestamp.addingTimeInterval(-retention)
        samples.removeAll { $0.timestamp < cutoff }

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(samples).write(to: fileURL, options: .atomic)
    }

    /// Moves a bad log aside so the failure stays inspectable instead of
    /// vanishing. Only ever one such file — an older one is replaced.
    private func setAsideCorruptFile() {
        let fm = FileManager.default
        try? fm.removeItem(at: corruptFileURL)
        try? fm.moveItem(at: fileURL, to: corruptFileURL)
        try? fm.removeItem(at: fileURL)
    }
}
