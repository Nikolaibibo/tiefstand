# History Graph Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a second screen to the menu-bar popover that plots the last 7 or 30 days — the national Dryness Index and the local gauge — reached by clicking the headline number.

**Architecture:** Two sources with opposite characteristics feed one chart. The Dryness Index has no history anywhere, so the app records its own samples to an append-only JSON log; the gauge curve is fetched on demand from PEGELONLINE, which serves a rolling 30 days at 15-minute resolution. A pure `TrendSeries` value type sits between both and the renderer, so the `Canvas`-based chart never learns where its points came from.

**Tech Stack:** Swift 5.9 language mode (Swift 6.3 toolchain), SwiftUI, `Canvas`, `URLSession`, `Codable`, XCTest. No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-08-15-history-graph-design.md`

## Global Constraints

- `// swift-tools-version:5.9`, `platforms: [.macOS(.v14)]` — do not raise either.
- **`TiefstandCore` is Foundation-only.** No `SwiftUI`, `AppKit` or `WidgetKit` imports in that target — it is what keeps the logic unit-testable without a host app.
- Only `TiefstandCoreTests` exists as a test target. UI code is verified by building and running, not by unit tests.
- All user-facing copy is **English**. Code comments are English.
- Every outbound request sends `NIWISProvider.userAgent` (`"Tiefstand/0.1 (+https://github.com/Nikolaibibo/tiefstand)"`).
- **Gauge history is fetched only on user action**, never on a timer. The app's own poll interval stays `7200` seconds (`IndexModel.startAutoRefreshing`).
- `Canvas` renders fine inside the popover (`Donut` already uses it) but **not** in the `MenuBarExtra` label. Do not put `Canvas` in the label.
- The existing 13 tests must stay green. Run `swift test` before every commit.
- Distance constants, verbatim: exact match tolerance **2 000 m**, hard ceiling **25 000 m**.
- Retention, verbatim: **400 days** (`400 * 86_400` seconds).
- Gap thresholds, verbatim: index **6 h** (`21_600`), gauge **3 h** (`10_800`).
- Downsample targets, verbatim: **160** points for a 7-day window, **31** for a 30-day window.

---

### Task 1: Split `Views.swift`

Pure move, no logic change. `Views.swift` is 384 lines and the largest file in the repo; this task adds nothing but makes room for a second screen. Keep it as its own commit so the real diffs later are readable.

**Files:**
- Create: `Sources/Tiefstand/MenuBarGlyph.swift`
- Create: `Sources/Tiefstand/PopoverView.swift`
- Create: `Sources/Tiefstand/Cards.swift`
- Delete: `Sources/Tiefstand/Views.swift`
- Test: none (no behaviour change; the existing suite is the regression net)

**Interfaces:**
- Consumes: nothing.
- Produces: the same public types as before, unchanged — `MenuBarLabel`, `MenuBarGlyph`, `WaveFillShape`, `WaveSurfaceLine`, `PopoverView`, `LoginItem`, `niwisURL`, `openExternally(_:)`, `DomainCard`, `Donut`, `LocalStationCard`.

- [ ] **Step 1: Record the current baseline**

```bash
cd ~/Documents/web/tiefstand
swift test 2>&1 | tail -5
```

Expected: `Executed 13 tests, with 0 failures`. Write the number down — Task 1 must not change it.

- [ ] **Step 2: Create `MenuBarGlyph.swift`**

Move these declarations out of `Views.swift` **verbatim**, in this order: `MenuBarLabel`, `MenuBarGlyph`, the file-private `waveSurface(in:fraction:)` function, `WaveFillShape`, `WaveSurfaceLine`. Keep every doc comment.

File header:

```swift
import SwiftUI
import AppKit
import TiefstandUI
```

`waveSurface` stays `private` — both shapes that use it live in this file, so file scope is still enough.

- [ ] **Step 3: Create `Cards.swift`**

Move `DomainCard`, `Donut` and `LocalStationCard` verbatim.

```swift
import SwiftUI
import AppKit
import TiefstandCore
import TiefstandUI
```

- [ ] **Step 4: Create `PopoverView.swift`**

Move what remains: `niwisURL`, `openExternally(_:)`, `LoginItem`, `PopoverView`.

```swift
import SwiftUI
import AppKit
import ServiceManagement
import TiefstandCore
import TiefstandUI
```

- [ ] **Step 5: Delete `Views.swift` and build**

```bash
rm Sources/Tiefstand/Views.swift
swift build 2>&1 | tail -5
```

Expected: `Build complete`. A "cannot find X in scope" error means a declaration was dropped in the move — put it back rather than reimplementing it.

- [ ] **Step 6: Verify nothing changed but the layout**

```bash
swift test 2>&1 | tail -5
git diff --stat HEAD
```

Expected: still 13 tests, 0 failures. The diff should show only the three new files plus the deleted one, and the total added lines should be within ~15 of the deleted lines (the extra import headers).

- [ ] **Step 7: Commit**

```bash
git add -A Sources/Tiefstand
git commit -m "refactor(app): split Views.swift by responsibility

Pure move ahead of the history screen: menu-bar glyph, popover shell and
cards each get their own file. No behaviour change.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: `DrynessSample` and `IndexHistoryStore`

The durable record of the index. Nothing reads it yet.

**Files:**
- Create: `Sources/TiefstandCore/DrynessSample.swift`
- Create: `Sources/TiefstandCore/IndexHistoryStore.swift`
- Test: `Tests/TiefstandCoreTests/IndexHistoryStoreTests.swift`

**Interfaces:**
- Consumes: `DrynessIndex` (existing, `Sources/TiefstandCore/DrynessIndex.swift`) — has `value: Double`, `dischargeScore: Double?`, `groundwaterScore: Double?`.
- Produces:
  - `DrynessSample(timestamp: Date, index: Double, dischargeScore: Double?, groundwaterScore: Double?)`
  - `DrynessSample(index: DrynessIndex, timestamp: Date)`
  - `protocol IndexHistoryStoring { func append(_ sample: DrynessSample) throws; func load() -> [DrynessSample] }`
  - `IndexHistoryStore(fileURL: URL = IndexHistoryStore.defaultFileURL, retention: TimeInterval = IndexHistoryStore.defaultRetention)`, plus the statics `IndexHistoryStore.defaultFileURL` and `IndexHistoryStore.defaultRetention`

- [ ] **Step 1: Write the failing tests**

Create `Tests/TiefstandCoreTests/IndexHistoryStoreTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
swift test --filter IndexHistoryStoreTests 2>&1 | tail -20
```

Expected: compile failure — `cannot find 'DrynessSample' in scope`. That is the correct starting point.

- [ ] **Step 3: Write `DrynessSample.swift`**

```swift
import Foundation

/// One recorded observation of the national Dryness Index.
///
/// Both domain scores are stored even though only the combined index is
/// plotted today, so per-domain curves can be added later without a hole in
/// the record. Samples are the *only* source of index history — NIWIS serves
/// the current aggregate and nothing else, so whatever isn't recorded here is
/// gone for good.
public struct DrynessSample: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let index: Double
    public let dischargeScore: Double?
    public let groundwaterScore: Double?

    public init(timestamp: Date,
                index: Double,
                dischargeScore: Double?,
                groundwaterScore: Double?) {
        self.timestamp = timestamp
        self.index = index
        self.dischargeScore = dischargeScore
        self.groundwaterScore = groundwaterScore
    }

    /// Snapshots a freshly computed index.
    public init(index: DrynessIndex, timestamp: Date) {
        self.init(timestamp: timestamp,
                  index: index.value,
                  dischargeScore: index.dischargeScore,
                  groundwaterScore: index.groundwaterScore)
    }
}
```

- [ ] **Step 4: Write `IndexHistoryStore.swift`**

```swift
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
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
swift test --filter IndexHistoryStoreTests 2>&1 | tail -5
```

Expected: `Executed 8 tests, with 0 failures`.

- [ ] **Step 6: Run the whole suite**

```bash
swift test 2>&1 | tail -5
```

Expected: `Executed 21 tests, with 0 failures` (13 existing + 8 new).

- [ ] **Step 7: Commit**

```bash
git add Sources/TiefstandCore/DrynessSample.swift \
        Sources/TiefstandCore/IndexHistoryStore.swift \
        Tests/TiefstandCoreTests/IndexHistoryStoreTests.swift
git commit -m "feat(core): record index samples to an append-only log (TDD)

NIWIS serves only the current aggregate, so the Dryness Index has no
history anywhere but here. 400-day retention; a corrupt log is set aside
rather than allowed to break startup.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Record a sample on every successful refresh

Three lines in the app target. `IndexModel` is not covered by the test target, so the behaviour is verified by building and running.

**Files:**
- Modify: `Sources/Tiefstand/TiefstandApp.swift` (`IndexModel`, lines ~22–96)

**Interfaces:**
- Consumes: `IndexHistoryStoring`, `IndexHistoryStore`, `DrynessSample(index:timestamp:)` from Task 2.
- Produces: `IndexModel(provider:history:)` — a second parameter with a default, so existing call sites keep working.

- [ ] **Step 1: Add the injected store**

In `TiefstandApp.swift`, replace the stored properties and initialiser of `IndexModel`:

```swift
    private let provider: DataProvider
    private let history: IndexHistoryStoring
    private var autoRefreshTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?

    init(provider: DataProvider = NIWISProvider(),
         history: IndexHistoryStoring = IndexHistoryStore()) {
        self.provider = provider
        self.history = history
        startAutoRefreshing()
        observeWake()
    }
```

- [ ] **Step 2: Record inside the success path**

In `refresh()`, inside the `withAnimation(.easeInOut)` block, the index is assigned as:

```swift
                index = DrynessIndex.combined(discharge: dd, groundwater: gg)
```

Immediately **after** the closing brace of that `withAnimation` block — and before `} catch {` — add:

```swift
            // The only place index history is ever created. A failed write must
            // never surface as a refresh error: a missing sample is a gap in a
            // chart, not a broken app.
            if let index {
                try? history.append(DrynessSample(index: index, timestamp: updatedAt ?? Date()))
            }
```

- [ ] **Step 3: Build**

```bash
swift build 2>&1 | tail -5
```

Expected: `Build complete`.

- [ ] **Step 4: Run the app and confirm a sample lands on disk**

```bash
./Scripts/make-app.sh --run
sleep 20
cat ~/Library/Application\ Support/Tiefstand/index-history.json
```

Expected: a JSON array with one object carrying `timestamp`, `index`, and both domain scores. If the file is missing, the refresh failed — check the popover footer for an error before touching the store code.

- [ ] **Step 5: Run the suite and commit**

```bash
swift test 2>&1 | tail -5
git add Sources/Tiefstand/TiefstandApp.swift
git commit -m "feat(app): record a Dryness Index sample after each refresh

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: `TrendSeries`

The largest piece of logic and the seam both data sources meet at. Pure, no I/O.

**Files:**
- Create: `Sources/TiefstandCore/TrendSeries.swift`
- Test: `Tests/TiefstandCoreTests/TrendSeriesTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `TrendPoint(date: Date, value: Double)`
  - `TrendSegment(points: [TrendPoint])`
  - `YScale.fixed(ClosedRange<Double>)` / `YScale.auto`
  - `TrendSeries(segments:window:yScale:unit:coverage:)`, plus `isEmpty: Bool` and `allPoints: [TrendPoint]`
  - `TrendSeries.make(from:window:gapThreshold:maxPoints:yScale:unit:) -> TrendSeries`

- [ ] **Step 1: Write the failing tests**

Create `Tests/TiefstandCoreTests/TrendSeriesTests.swift`:

```swift
import XCTest
@testable import TiefstandCore

final class TrendSeriesTests: XCTestCase {

    private let start = Date(timeIntervalSince1970: 1_786_000_000)

    /// `count` points, `spacing` apart, starting at `from`.
    private func points(count: Int, spacing: TimeInterval,
                        from: Date, value: Double = 50) -> [TrendPoint] {
        (0..<count).map {
            TrendPoint(date: from.addingTimeInterval(Double($0) * spacing), value: value)
        }
    }

    private func window(days: Double, endingAt end: Date) -> ClosedRange<Date> {
        end.addingTimeInterval(-days * 86_400)...end
    }

    func test_pointsOutsideTheWindowAreExcluded() {
        let end = start.addingTimeInterval(30 * 86_400)
        let inside = TrendPoint(date: start.addingTimeInterval(86_400), value: 40)
        let outside = TrendPoint(date: start.addingTimeInterval(-86_400), value: 90)

        let series = TrendSeries.make(from: [outside, inside],
                                      window: start...end,
                                      gapThreshold: 21_600,
                                      maxPoints: 160,
                                      yScale: .fixed(0...100),
                                      unit: "")

        XCTAssertEqual(series.allPoints.map(\.value), [40])
    }

    func test_inputIsSortedByDate() {
        let end = start.addingTimeInterval(7 * 86_400)
        let later = TrendPoint(date: start.addingTimeInterval(2 * 3_600), value: 20)
        let earlier = TrendPoint(date: start.addingTimeInterval(1 * 3_600), value: 10)

        let series = TrendSeries.make(from: [later, earlier],
                                      window: start...end,
                                      gapThreshold: 21_600,
                                      maxPoints: 160,
                                      yScale: .auto,
                                      unit: "cm")

        XCTAssertEqual(series.allPoints.map(\.value), [10, 20])
    }

    func test_sevenDayWindowDownsamplesTo160PointsOrFewer() {
        // 672 points = 7 days at PEGELONLINE's 15-minute cadence.
        let end = start.addingTimeInterval(7 * 86_400)
        let raw = points(count: 672, spacing: 900, from: start)

        let series = TrendSeries.make(from: raw,
                                      window: start...end,
                                      gapThreshold: 10_800,
                                      maxPoints: 160,
                                      yScale: .auto,
                                      unit: "cm")

        XCTAssertLessThanOrEqual(series.allPoints.count, 160)
        XCTAssertGreaterThan(series.allPoints.count, 100)
    }

    func test_thirtyDayWindowBucketsToAtMost31DailyPoints() {
        // 2880 points = 30 days at 15-minute cadence.
        let end = start.addingTimeInterval(30 * 86_400)
        let raw = points(count: 2_880, spacing: 900, from: start)

        let series = TrendSeries.make(from: raw,
                                      window: start...end,
                                      gapThreshold: 10_800,
                                      maxPoints: 31,
                                      yScale: .auto,
                                      unit: "cm")

        XCTAssertLessThanOrEqual(series.allPoints.count, 31)
    }

    /// Regression guard for an ordering bug that is easy to reintroduce: with
    /// 30-day daily buckets the downsampled points sit ~24 h apart, far beyond
    /// the 3 h gauge gap threshold. If gaps were detected *after* downsampling,
    /// a perfectly continuous month would shatter into 31 one-point segments
    /// and the chart would draw dots instead of a line. Split first, then
    /// downsample inside each segment.
    func test_dailyBucketsDoNotShatterAContinuousMonthIntoSegments() {
        let end = start.addingTimeInterval(30 * 86_400)
        let raw = points(count: 2_880, spacing: 900, from: start)

        let series = TrendSeries.make(from: raw,
                                      window: start...end,
                                      gapThreshold: 10_800,
                                      maxPoints: 31,
                                      yScale: .auto,
                                      unit: "cm")

        XCTAssertEqual(series.segments.count, 1)
    }

    func test_downsamplingPreservesTheFirstAndLastTimestamps() {
        let end = start.addingTimeInterval(7 * 86_400)
        let raw = points(count: 672, spacing: 900, from: start)

        let series = TrendSeries.make(from: raw,
                                      window: start...end,
                                      gapThreshold: 10_800,
                                      maxPoints: 160,
                                      yScale: .auto,
                                      unit: "cm")

        XCTAssertEqual(series.allPoints.first?.date, raw.first?.date)
        XCTAssertEqual(series.allPoints.last?.date, raw.last?.date)
    }

    func test_downsamplingAveragesValuesWithinABucket() {
        let end = start.addingTimeInterval(2 * 86_400)
        let raw = [
            TrendPoint(date: start.addingTimeInterval(3_600), value: 10),
            TrendPoint(date: start.addingTimeInterval(7_200), value: 30),
            TrendPoint(date: start.addingTimeInterval(86_400 + 3_600), value: 100),
        ]

        let series = TrendSeries.make(from: raw,
                                      window: start...end,
                                      gapThreshold: 2 * 86_400,   // no split
                                      maxPoints: 2,
                                      yScale: .auto,
                                      unit: "")

        XCTAssertEqual(series.allPoints.map(\.value), [20, 100])
    }

    func test_contiguousPointsProduceExactlyOneSegment() {
        let end = start.addingTimeInterval(7 * 86_400)
        let raw = points(count: 24, spacing: 7_200, from: start)   // every 2 h

        let series = TrendSeries.make(from: raw,
                                      window: start...end,
                                      gapThreshold: 21_600,
                                      maxPoints: 160,
                                      yScale: .fixed(0...100),
                                      unit: "")

        XCTAssertEqual(series.segments.count, 1)
    }

    func test_aGapLongerThanTheThresholdSplitsTheSeriesInTwo() {
        let end = start.addingTimeInterval(7 * 86_400)
        let before = points(count: 5, spacing: 7_200, from: start)
        // 24 h later — well past the 6 h index threshold.
        let after = points(count: 5, spacing: 7_200,
                           from: start.addingTimeInterval(5 * 7_200 + 86_400))

        let series = TrendSeries.make(from: before + after,
                                      window: start...end,
                                      gapThreshold: 21_600,
                                      maxPoints: 160,
                                      yScale: .fixed(0...100),
                                      unit: "")

        XCTAssertEqual(series.segments.count, 2)
        XCTAssertEqual(series.segments[0].points.count, 5)
        XCTAssertEqual(series.segments[1].points.count, 5)
    }

    func test_coverageIsOneForAFullyCoveredWindow() {
        let end = start.addingTimeInterval(7 * 86_400)
        let raw = points(count: 85, spacing: 7_200, from: start)   // 7 days at 2 h

        let series = TrendSeries.make(from: raw,
                                      window: start...end,
                                      gapThreshold: 21_600,
                                      maxPoints: 160,
                                      yScale: .fixed(0...100),
                                      unit: "")

        XCTAssertEqual(series.coverage, 1.0, accuracy: 0.02)
    }

    func test_coverageReflectsTwoRecordedDaysOutOfThirty() {
        let end = start.addingTimeInterval(30 * 86_400)
        // Two days of samples at the 2 h poll cadence, at the end of the window.
        let raw = points(count: 25, spacing: 7_200,
                         from: end.addingTimeInterval(-2 * 86_400))

        let series = TrendSeries.make(from: raw,
                                      window: start...end,
                                      gapThreshold: 21_600,
                                      maxPoints: 31,
                                      yScale: .fixed(0...100),
                                      unit: "")

        XCTAssertEqual(series.coverage, 2.0 / 30.0, accuracy: 0.01)
    }

    func test_anEmptyInputProducesAnEmptySeriesWithZeroCoverage() {
        let end = start.addingTimeInterval(30 * 86_400)

        let series = TrendSeries.make(from: [],
                                      window: start...end,
                                      gapThreshold: 21_600,
                                      maxPoints: 31,
                                      yScale: .fixed(0...100),
                                      unit: "")

        XCTAssertTrue(series.isEmpty)
        XCTAssertEqual(series.coverage, 0)
    }

    func test_aSingleSampleIsKeptButCoversAlmostNothing() {
        let end = start.addingTimeInterval(30 * 86_400)
        let raw = [TrendPoint(date: end.addingTimeInterval(-3_600), value: 47)]

        let series = TrendSeries.make(from: raw,
                                      window: start...end,
                                      gapThreshold: 21_600,
                                      maxPoints: 31,
                                      yScale: .fixed(0...100),
                                      unit: "")

        XCTAssertEqual(series.allPoints.count, 1)
        XCTAssertEqual(series.coverage, 0, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
swift test --filter TrendSeriesTests 2>&1 | tail -20
```

Expected: compile failure — `cannot find 'TrendSeries' in scope`.

- [ ] **Step 3: Write `TrendSeries.swift`**

```swift
import Foundation

/// A single plotted observation.
public struct TrendPoint: Equatable, Sendable {
    public let date: Date
    public let value: Double

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

/// A contiguous run of points. A recording gap ends one segment and starts the
/// next, so the renderer draws a break instead of a straight line through data
/// that was never measured.
public struct TrendSegment: Equatable, Sendable {
    public let points: [TrendPoint]

    public init(points: [TrendPoint]) {
        self.points = points
    }
}

/// How the vertical axis is chosen.
public enum YScale: Equatable, Sendable {
    /// The Dryness Index is defined on 0–100; pinning the axis keeps the four
    /// severity bands meaningful and stops a flat week from looking dramatic.
    case fixed(ClosedRange<Double>)
    /// Gauge readings are centimetres with no natural bounds — fit the data.
    case auto
}

/// Drawable geometry, decoupled from where the numbers came from. The index
/// series is read from disk and the gauge series from the network, but the
/// chart only ever sees this.
public struct TrendSeries: Equatable, Sendable {
    public let segments: [TrendSegment]
    public let window: ClosedRange<Date>
    public let yScale: YScale
    public let unit: String
    /// 0…1 — how much of the window actually has data behind it. Drives the
    /// "n of 30 days" label on the index tab.
    public let coverage: Double

    public init(segments: [TrendSegment],
                window: ClosedRange<Date>,
                yScale: YScale,
                unit: String,
                coverage: Double) {
        self.segments = segments
        self.window = window
        self.yScale = yScale
        self.unit = unit
        self.coverage = coverage
    }

    public var allPoints: [TrendPoint] { segments.flatMap(\.points) }
    public var isEmpty: Bool { allPoints.isEmpty }

    /// Smallest and largest plotted value, or `nil` when empty.
    public var valueRange: ClosedRange<Double>? {
        let values = allPoints.map(\.value)
        guard let lo = values.min(), let hi = values.max() else { return nil }
        return lo == hi ? (lo - 1)...(hi + 1) : lo...hi
    }
}

public extension TrendSeries {

    /// Filter → **split on gaps** → downsample within each segment. Pure; no
    /// clock, no I/O.
    ///
    /// The order matters and is the one thing not to rearrange here. Gaps are
    /// found in the *raw* data, because downsampled points are deliberately far
    /// apart — a 30-day window buckets to one point per day, and comparing
    /// those 24 h spacings against a 3 h threshold would turn an unbroken month
    /// into 31 isolated dots.
    ///
    /// - Parameters:
    ///   - gapThreshold: an interval longer than this is a hole, not a line.
    ///     6 h for the index (3× its 2 h poll), 3 h for the gauge.
    ///   - maxPoints: 160 for a 7-day window, 31 for a 30-day window — the
    ///     latter being exactly one bucket per day.
    static func make(from points: [TrendPoint],
                     window: ClosedRange<Date>,
                     gapThreshold: TimeInterval,
                     maxPoints: Int,
                     yScale: YScale,
                     unit: String) -> TrendSeries {
        let inWindow = points
            .filter { window.contains($0.date) }
            .sorted { $0.date < $1.date }

        var segments = split(inWindow, gapThreshold: gapThreshold).map {
            TrendSegment(points: downsample($0.points, window: window, maxPoints: maxPoints))
        }
        pinEnds(of: &segments, to: inWindow)

        return TrendSeries(
            segments: segments,
            window: window,
            yScale: yScale,
            unit: unit,
            coverage: coverage(of: inWindow, in: window, gapThreshold: gapThreshold))
    }

    /// Time-bucket averaging on a grid aligned to the window start, so the
    /// output is stable between refreshes rather than shifting with every new
    /// point — and so segments downsampled separately still line up on one grid.
    private static func downsample(_ points: [TrendPoint],
                                   window: ClosedRange<Date>,
                                   maxPoints: Int) -> [TrendPoint] {
        guard maxPoints > 0, points.count > maxPoints else { return points }

        let span = window.upperBound.timeIntervalSince(window.lowerBound)
        guard span > 0 else { return points }
        let bucketWidth = span / Double(maxPoints)

        var buckets: [Int: [TrendPoint]] = [:]
        for point in points {
            let offset = point.date.timeIntervalSince(window.lowerBound)
            let bucket = min(maxPoints - 1, max(0, Int(offset / bucketWidth)))
            buckets[bucket, default: []].append(point)
        }

        return buckets.keys.sorted().compactMap { key in
            guard let group = buckets[key], !group.isEmpty else { return nil }
            let meanValue = group.reduce(0) { $0 + $1.value } / Double(group.count)
            let meanDate = Date(timeIntervalSinceReferenceDate:
                group.reduce(0) { $0 + $1.date.timeIntervalSinceReferenceDate } / Double(group.count))
            return TrendPoint(date: meanDate, value: meanValue)
        }
    }

    /// Anchors the very first and very last plotted points to the real
    /// observations, so a downsampled curve doesn't visibly shrink away from
    /// the edges of the chart. Only the outer ends move; interior bucket dates
    /// stay on the grid.
    private static func pinEnds(of segments: inout [TrendSegment], to raw: [TrendPoint]) {
        guard !segments.isEmpty, let firstRaw = raw.first, let lastRaw = raw.last else { return }

        if var points = segments.first?.points, let head = points.first {
            points[0] = TrendPoint(date: firstRaw.date, value: head.value)
            segments[0] = TrendSegment(points: points)
        }
        if var points = segments.last?.points, let tail = points.last {
            points[points.count - 1] = TrendPoint(date: lastRaw.date, value: tail.value)
            segments[segments.count - 1] = TrendSegment(points: points)
        }
    }

    private static func split(_ points: [TrendPoint],
                              gapThreshold: TimeInterval) -> [TrendSegment] {
        guard !points.isEmpty else { return [] }

        var segments: [TrendSegment] = []
        var current: [TrendPoint] = [points[0]]

        for point in points.dropFirst() {
            let previous = current[current.count - 1].date
            if point.date.timeIntervalSince(previous) > gapThreshold {
                segments.append(TrendSegment(points: current))
                current = [point]
            } else {
                current.append(point)
            }
        }
        segments.append(TrendSegment(points: current))
        return segments
    }

    /// Sums the intervals that are short enough to count as "covered" and
    /// divides by the window length. Deliberately computed from the raw points,
    /// before downsampling, so it describes the recording and not the drawing.
    private static func coverage(of points: [TrendPoint],
                                 in window: ClosedRange<Date>,
                                 gapThreshold: TimeInterval) -> Double {
        let span = window.upperBound.timeIntervalSince(window.lowerBound)
        guard span > 0, points.count > 1 else { return 0 }

        let covered = zip(points, points.dropFirst()).reduce(0.0) { total, pair in
            let delta = pair.1.date.timeIntervalSince(pair.0.date)
            return delta <= gapThreshold ? total + delta : total
        }
        return min(1, covered / span)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
swift test --filter TrendSeriesTests 2>&1 | tail -5
```

Expected: `Executed 13 tests, with 0 failures`.

If `test_sevenDayWindowDownsamplesTo160PointsOrFewer` fails on the lower bound, the bucket alignment is off — 672 points over exactly 7 days into 160 buckets should fill roughly 160 of them.

If `test_dailyBucketsDoNotShatterAContinuousMonthIntoSegments` fails, `split` is running after `downsample`. Re-read the ordering note on `make`.

- [ ] **Step 5: Run the whole suite and commit**

```bash
swift test 2>&1 | tail -5
git add Sources/TiefstandCore/TrendSeries.swift Tests/TiefstandCoreTests/TrendSeriesTests.swift
git commit -m "feat(core): TrendSeries — filter, downsample, split on gaps (TDD)

The seam both history sources meet at. Gaps become separate segments so a
weekend with the lid shut reads as a gap, not as interpolated data.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

Expected: `Executed 34 tests, with 0 failures`.

---

### Task 5: PEGELONLINE gauge history

Network access for the gauge curve, plus the on-disk cache for the station list.

**Files:**
- Create: `Sources/TiefstandCore/GaugeHistory.swift`
- Test: `Tests/TiefstandCoreTests/GaugeHistoryTests.swift`

**Interfaces:**
- Consumes: `NIWISProvider.userAgent` (existing, `Sources/TiefstandCore/NIWISProvider.swift`).
- Produces:
  - `GaugeStation` with `uuid: String`, `shortname: String`, `longname: String`, `longitude: Double?`, `latitude: Double?`, `water: GaugeStation.Water?`
  - `GaugeMeasurement(timestamp: Date, value: Double)`
  - `protocol GaugeHistoryProviding { func stations() async throws -> [GaugeStation]; func measurements(uuid: String, days: Int) async throws -> [GaugeMeasurement] }`
  - `PEGELONLINEHistoryProvider(baseURL:session:stationCache:)`
  - `GaugeStationCache(fileURL:maxAge:)` with `read(now:) -> [GaugeStation]?`, `write(_:now:) throws` and the static `GaugeStationCache.default`
  - `GaugeMeasurement.trendPoint: TrendPoint`

- [ ] **Step 1: Write the failing tests**

Create `Tests/TiefstandCoreTests/GaugeHistoryTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
swift test --filter GaugeHistoryTests 2>&1 | tail -20
```

Expected: compile failure — `cannot find 'PEGELONLINEHistoryProvider' in scope`.

- [ ] **Step 3: Write `GaugeHistory.swift`**

```swift
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
```

Note the `Envelope` uses the default date strategy on both sides, so encoding and decoding agree without extra configuration.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
swift test --filter GaugeHistoryTests 2>&1 | tail -5
```

Expected: `Executed 8 tests, with 0 failures`.

- [ ] **Step 5: Confirm the live endpoint still matches the fixtures**

One request, to catch a shape change before it becomes a runtime bug:

```bash
curl -s -A "Tiefstand/0.1 (+https://github.com/Nikolaibibo/tiefstand)" \
  "https://www.pegelonline.wsv.de/webservices/rest-api/v2/stations/b475386c-30cc-453a-b3b7-1d17ace13595/W/measurements.json?start=P1D" \
  | head -c 200
```

Expected: a JSON array of `{"timestamp": "...", "value": ...}` objects. If the shape differs, fix the fixtures in the test first, then the decoder.

- [ ] **Step 6: Run the whole suite and commit**

```bash
swift test 2>&1 | tail -5
git add Sources/TiefstandCore/GaugeHistory.swift Tests/TiefstandCoreTests/GaugeHistoryTests.swift
git commit -m "feat(core): PEGELONLINE gauge history + station cache (TDD)

30 days of water level at 15-minute resolution, fetched on demand only.
The station list is cached on disk for 30 days — it is 262 KB and static.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

Expected: `Executed 42 tests, with 0 failures`.

---

### Task 6: `GaugeMatcher`

The bridge between NIWIS station IDs (`DESM_DEBY16607001`) and PEGELONLINE UUIDs. There is no crosswalk, so matching is geographic.

**Files:**
- Create: `Sources/TiefstandCore/GaugeMatcher.swift`
- Test: `Tests/TiefstandCoreTests/GaugeMatcherTests.swift`

**Interfaces:**
- Consumes: `GaugeStation` (Task 5), `Coordinate` (existing, `StationReading.swift` — `longitude`, `latitude`).
- Produces:
  - `GaugeMatch(station: GaugeStation, distanceMeters: Double)` with `isExact: Bool`
  - `GaugeMatcher.exactToleranceMeters` = `2_000`, `GaugeMatcher.maximumDistanceMeters` = `25_000`
  - `GaugeMatcher.nearest(to: Coordinate, in: [GaugeStation]) -> GaugeMatch?`
  - `GaugeMatcher.distanceMeters(from: Coordinate, to: Coordinate) -> Double`

- [ ] **Step 1: Write the failing tests**

Create `Tests/TiefstandCoreTests/GaugeMatcherTests.swift`:

```swift
import XCTest
@testable import TiefstandCore

final class GaugeMatcherTests: XCTestCase {

    private func station(_ name: String, lat: Double?, lon: Double?) -> GaugeStation {
        GaugeStation(uuid: name.lowercased(), shortname: name, longname: name,
                     longitude: lon, latitude: lat,
                     water: GaugeStation.Water(shortname: "ALLER", longname: "ALLER"))
    }

    private let celle = Coordinate(longitude: 10.062164, latitude: 52.622706)

    func test_oneDegreeOfLatitudeIsAboutOneHundredElevenKilometres() {
        let distance = GaugeMatcher.distanceMeters(
            from: Coordinate(longitude: 10, latitude: 52),
            to: Coordinate(longitude: 10, latitude: 53))

        XCTAssertEqual(distance, 111_195, accuracy: 1_112)   // within 1 %
    }

    func test_identicalCoordinatesAreZeroApart() {
        XCTAssertEqual(GaugeMatcher.distanceMeters(from: celle, to: celle), 0, accuracy: 0.001)
    }

    func test_picksTheNearestOfSeveralGauges() {
        let near = station("NEAR", lat: 52.6228, lon: 10.0622)      // ~10 m
        let far = station("FAR", lat: 52.70, lon: 10.30)            // ~17 km

        let match = GaugeMatcher.nearest(to: celle, in: [far, near])

        XCTAssertEqual(match?.station.shortname, "NEAR")
    }

    func test_aGaugeWithinTwoKilometresCountsAsTheSameStation() {
        // ~1.1 km north.
        let match = GaugeMatcher.nearest(to: celle, in: [station("CELLE", lat: 52.6327, lon: 10.062164)])

        XCTAssertNotNil(match)
        XCTAssertTrue(match!.isExact)
    }

    func test_aGaugeJustBeyondTwoKilometresIsStillReturnedButNotExact() {
        // ~2.8 km north.
        let match = GaugeMatcher.nearest(to: celle, in: [station("NEARBY", lat: 52.6479, lon: 10.062164)])

        XCTAssertNotNil(match)
        XCTAssertFalse(match!.isExact)
        XCTAssertGreaterThan(match!.distanceMeters, GaugeMatcher.exactToleranceMeters)
    }

    func test_theNearestGaugeBeyondTwentyFiveKilometresIsRejected() {
        // ~55 km north — a different river, not "this station's history".
        let match = GaugeMatcher.nearest(to: celle, in: [station("ELSEWHERE", lat: 53.12, lon: 10.062164)])

        XCTAssertNil(match)
    }

    func test_stationsWithoutCoordinatesAreSkipped() {
        let placeable = station("NEAR", lat: 52.6228, lon: 10.0622)
        let unplaceable = station("NOWHERE", lat: nil, lon: nil)

        let match = GaugeMatcher.nearest(to: celle, in: [unplaceable, placeable])

        XCTAssertEqual(match?.station.shortname, "NEAR")
    }

    func test_anEmptyStationListHasNoMatch() {
        XCTAssertNil(GaugeMatcher.nearest(to: celle, in: []))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
swift test --filter GaugeMatcherTests 2>&1 | tail -20
```

Expected: compile failure — `cannot find 'GaugeMatcher' in scope`.

- [ ] **Step 3: Write `GaugeMatcher.swift`**

```swift
import Foundation

/// A PEGELONLINE gauge proposed as the history source for a NIWIS station,
/// carrying how far away it actually is.
public struct GaugeMatch: Equatable, Sendable {
    public let station: GaugeStation
    public let distanceMeters: Double

    public init(station: GaugeStation, distanceMeters: Double) {
        self.station = station
        self.distanceMeters = distanceMeters
    }

    /// Close enough to present as the same gauge, with no caveat in the UI.
    public var isExact: Bool { distanceMeters <= GaugeMatcher.exactToleranceMeters }
}

/// Bridges two systems that share no identifiers: NIWIS station IDs look like
/// `DESM_DEBY16607001`, PEGELONLINE uses UUIDs. Matching is therefore purely
/// geographic.
public enum GaugeMatcher {

    /// Within this distance the two records are treated as the same gauge.
    public static let exactToleranceMeters = 2_000.0

    /// Beyond this, no match is offered at all. A gauge 80 km away on another
    /// river is not this station's history, and showing it anyway would be a
    /// quiet lie — better an honest empty state.
    public static let maximumDistanceMeters = 25_000.0

    private static let earthRadiusMeters = 6_371_000.0

    /// Great-circle distance. Haversine rather than Core Location so this stays
    /// in a Foundation-only target and testable without a device.
    public static func distanceMeters(from a: Coordinate, to b: Coordinate) -> Double {
        let φ1 = a.latitude * .pi / 180
        let φ2 = b.latitude * .pi / 180
        let dφ = (b.latitude - a.latitude) * .pi / 180
        let dλ = (b.longitude - a.longitude) * .pi / 180

        let h = sin(dφ / 2) * sin(dφ / 2)
              + cos(φ1) * cos(φ2) * sin(dλ / 2) * sin(dλ / 2)
        return 2 * earthRadiusMeters * atan2(sqrt(h), sqrt(1 - h))
    }

    /// The closest placeable gauge, or `nil` if the closest one is further away
    /// than `maximumDistanceMeters`.
    public static func nearest(to coordinate: Coordinate,
                               in stations: [GaugeStation]) -> GaugeMatch? {
        let candidates: [GaugeMatch] = stations.compactMap { station in
            guard let lat = station.latitude, let lon = station.longitude else { return nil }
            let distance = distanceMeters(
                from: coordinate,
                to: Coordinate(longitude: lon, latitude: lat))
            return GaugeMatch(station: station, distanceMeters: distance)
        }

        guard let closest = candidates.min(by: { $0.distanceMeters < $1.distanceMeters }),
              closest.distanceMeters <= maximumDistanceMeters
        else { return nil }
        return closest
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
swift test --filter GaugeMatcherTests 2>&1 | tail -5
```

Expected: `Executed 8 tests, with 0 failures`.

- [ ] **Step 5: Measure the real hit rate**

This is spec risk 1 and the plan should not close without a number. Write a throwaway script that pulls both live lists and reports how often a NIWIS discharge station finds a gauge:

```bash
cat > /tmp/hitrate.py <<'PY'
import json, math, urllib.request
UA = {"User-Agent": "Tiefstand/0.1 (+https://github.com/Nikolaibibo/tiefstand)"}
def get(u):
    return json.load(urllib.request.urlopen(urllib.request.Request(u, headers=UA)))
niwis = get("https://niwis-online.de/api/karte/messstelle/ABFLUSS?klassifikationsart=DYNAMISCH")
po = get("https://www.pegelonline.wsv.de/webservices/rest-api/v2/stations.json")
po = [s for s in po if s.get("latitude") is not None]
def dist(a1, o1, a2, o2):
    p1, p2 = math.radians(a1), math.radians(a2)
    dp, dl = math.radians(a2 - a1), math.radians(o2 - o1)
    h = math.sin(dp/2)**2 + math.cos(p1)*math.cos(p2)*math.sin(dl/2)**2
    return 2 * 6371000 * math.atan2(math.sqrt(h), math.sqrt(1-h))
exact = near = none = 0
for s in niwis:
    c = s.get("koordinate") or {}
    if c.get("y") is None: continue
    d = min(dist(c["y"], c["x"], p["latitude"], p["longitude"]) for p in po)
    if d <= 2000: exact += 1
    elif d <= 25000: near += 1
    else: none += 1
total = exact + near + none
print(f"{total} NIWIS discharge stations: {exact} exact (<=2km), {near} nearby (<=25km), {none} none")
PY
python3 /tmp/hitrate.py
```

Record the three numbers in the spec under risk 1, replacing "should be measured", then delete the script. If "none" exceeds roughly a third, raise it before continuing — the empty state would be the common case, not the exception, and that changes what the Gauge tab should default to.

- [ ] **Step 6: Run the whole suite and commit**

```bash
swift test 2>&1 | tail -5
git add Sources/TiefstandCore/GaugeMatcher.swift \
        Tests/TiefstandCoreTests/GaugeMatcherTests.swift \
        docs/superpowers/specs/2026-08-15-history-graph-design.md
git commit -m "feat(core): match NIWIS stations to PEGELONLINE gauges (TDD)

The two systems share no identifiers, so matching is geographic: same
gauge within 2 km, disclosed fallback to 25 km, nothing beyond that.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

Expected: `Executed 50 tests, with 0 failures`.

---

### Task 7: `TrendChart`

The renderer. `Canvas`-based, matching `WaveGauge` and `Donut`. No unit tests — the repo has none for UI; verification is building and looking at it.

**Files:**
- Create: `Sources/TiefstandUI/TrendChart.swift`

**Interfaces:**
- Consumes: `TrendSeries`, `TrendSegment`, `TrendPoint`, `YScale` (Task 4); `Hydro`, `DrynessLevel.color` (existing, `Sources/TiefstandUI/Theme.swift`).
- Produces: `TrendChart(series: TrendSeries, showsSeverityBands: Bool)` — a `View`.

- [ ] **Step 1: Write `TrendChart.swift`**

```swift
import SwiftUI
import TiefstandCore

/// Line chart for a `TrendSeries`, drawn with `Canvas` to match `WaveGauge`
/// and `Donut`. `Canvas` is fine here — the restriction only applies to the
/// `MenuBarExtra` label.
///
/// Each `TrendSegment` becomes its own path, so a recording gap shows as a
/// break rather than a line through data that was never measured.
public struct TrendChart: View {
    private let series: TrendSeries
    private let showsSeverityBands: Bool

    /// - Parameter showsSeverityBands: draws the four `DrynessLevel` bands
    ///   behind the curve. Meaningful for the 0–100 index, meaningless for
    ///   centimetres.
    public init(series: TrendSeries, showsSeverityBands: Bool) {
        self.series = series
        self.showsSeverityBands = showsSeverityBands
    }

    private var bounds: ClosedRange<Double> {
        switch series.yScale {
        case .fixed(let range):
            return range
        case .auto:
            guard let range = series.valueRange else { return 0...1 }
            let padding = max(1, (range.upperBound - range.lowerBound) * 0.12)
            return (range.lowerBound - padding)...(range.upperBound + padding)
        }
    }

    /// The point under the cursor, or `nil` when not hovering.
    @State private var hovered: TrendPoint?

    public var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    plot
                    yAxisLabels
                    if let hovered { readout(for: hovered) }
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        hovered = nearestPoint(toX: location.x, width: geometry.size.width)
                    case .ended:
                        hovered = nil
                    }
                }
            }
            xAxisLabels
        }
    }

    private var plot: some View {
        Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            if showsSeverityBands { drawSeverityBands(&ctx, in: rect) }
            drawGridLines(&ctx, in: rect)
            for segment in series.segments {
                drawSegment(segment, &ctx, in: rect)
            }
            if let hovered { drawCrosshair(hovered, &ctx, in: rect) }
        }
    }

    // MARK: axes

    /// Three ticks — top, middle, bottom — laid over the right edge of the plot
    /// rather than in a gutter, so the 320 pt popover keeps its drawing width.
    private var yAxisLabels: some View {
        let range = bounds
        return VStack(spacing: 0) {
            axisText(range.upperBound)
            Spacer(minLength: 0)
            axisText((range.lowerBound + range.upperBound) / 2)
            Spacer(minLength: 0)
            axisText(range.lowerBound)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }

    private func axisText(_ value: Double) -> some View {
        Text(String(format: "%.0f", value))
            .font(.system(size: 8, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 3)
            .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 3))
    }

    /// Four evenly spaced dates across the window, outer two flush to the edges.
    private var xTicks: [Date] {
        let lower = series.window.lowerBound
        let span = series.window.upperBound.timeIntervalSince(lower)
        return (0..<4).map { lower.addingTimeInterval(span * Double($0) / 3) }
    }

    private var xAxisLabels: some View {
        HStack(spacing: 0) {
            ForEach(Array(xTicks.enumerated()), id: \.offset) { index, date in
                Text(date.formatted(.dateTime.day().month(.abbreviated)))
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity,
                           alignment: index == 0 ? .leading
                                    : index == 3 ? .trailing : .center)
            }
        }
    }

    // MARK: hover

    private func nearestPoint(toX pointerX: CGFloat, width: CGFloat) -> TrendPoint? {
        guard width > 0 else { return nil }
        let span = series.window.upperBound.timeIntervalSince(series.window.lowerBound)
        let fraction = max(0, min(1, Double(pointerX / width)))
        let target = series.window.lowerBound.addingTimeInterval(span * fraction)
        return series.allPoints.min {
            abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target))
        }
    }

    private func readout(for point: TrendPoint) -> some View {
        let stamp = point.date.formatted(.dateTime.day().month(.abbreviated).hour().minute())
        let value = String(format: "%.0f", point.value)
        return Text(series.unit.isEmpty ? "\(stamp) · \(value)" : "\(stamp) · \(value) \(series.unit)")
            .font(.system(size: 9, design: .rounded))
            .monospacedDigit()
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .padding(4)
    }

    // MARK: geometry

    private func x(for date: Date, in rect: CGRect) -> CGFloat {
        let span = series.window.upperBound.timeIntervalSince(series.window.lowerBound)
        guard span > 0 else { return rect.midX }
        let t = date.timeIntervalSince(series.window.lowerBound) / span
        return rect.minX + rect.width * max(0, min(1, t))
    }

    private func y(for value: Double, in rect: CGRect) -> CGFloat {
        let range = bounds
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return rect.midY }
        let t = (value - range.lowerBound) / span
        return rect.maxY - rect.height * max(0, min(1, t))
    }

    // MARK: drawing

    /// Normal / elevated / high / severe as faint horizontal bands, so a value
    /// can be read qualitatively without consulting the axis.
    private func drawSeverityBands(_ ctx: inout GraphicsContext, in rect: CGRect) {
        let cuts: [(ClosedRange<Double>, DrynessLevel)] = [
            (0...25, .normal), (25...50, .elevated), (50...75, .high), (75...100, .severe),
        ]
        for (range, level) in cuts {
            let top = y(for: range.upperBound, in: rect)
            let bottom = y(for: range.lowerBound, in: rect)
            let band = CGRect(x: rect.minX, y: top, width: rect.width, height: bottom - top)
            ctx.fill(Path(band), with: .color(level.color.opacity(0.08)))
        }
    }

    private func drawGridLines(_ ctx: inout GraphicsContext, in rect: CGRect) {
        let range = bounds
        for fraction in [0.0, 0.5, 1.0] {
            let value = range.lowerBound + (range.upperBound - range.lowerBound) * fraction
            let lineY = y(for: value, in: rect)
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: lineY))
            path.addLine(to: CGPoint(x: rect.maxX, y: lineY))
            ctx.stroke(path, with: .color(.secondary.opacity(0.12)), lineWidth: 0.5)
        }
    }

    private func drawCrosshair(_ point: TrendPoint,
                               _ ctx: inout GraphicsContext,
                               in rect: CGRect) {
        let px = x(for: point.date, in: rect)
        let py = y(for: point.value, in: rect)

        var line = Path()
        line.move(to: CGPoint(x: px, y: rect.minY))
        line.addLine(to: CGPoint(x: px, y: rect.maxY))
        ctx.stroke(line, with: .color(.secondary.opacity(0.35)),
                   style: StrokeStyle(lineWidth: 0.75, dash: [2, 2]))

        let dot = CGRect(x: px - 3, y: py - 3, width: 6, height: 6)
        ctx.fill(Path(ellipseIn: dot), with: .color(.white))
        ctx.stroke(Path(ellipseIn: dot), with: .color(.secondary), lineWidth: 1)
    }

    private func drawSegment(_ segment: TrendSegment,
                             _ ctx: inout GraphicsContext,
                             in rect: CGRect) {
        let points = segment.points.map {
            CGPoint(x: x(for: $0.date, in: rect), y: y(for: $0.value, in: rect))
        }
        guard let first = points.first else { return }

        // A lone point would draw nothing as a path, so mark it as a dot.
        guard points.count > 1 else {
            let dot = CGRect(x: first.x - 2, y: first.y - 2, width: 4, height: 4)
            ctx.fill(Path(ellipseIn: dot), with: .color(tint(for: segment)))
            return
        }

        var line = Path()
        line.move(to: first)
        for point in points.dropFirst() { line.addLine(to: point) }

        var area = line
        area.addLine(to: CGPoint(x: points[points.count - 1].x, y: rect.maxY))
        area.addLine(to: CGPoint(x: first.x, y: rect.maxY))
        area.closeSubpath()

        let color = tint(for: segment)
        ctx.fill(area, with: .linearGradient(
            Gradient(colors: [color.opacity(0.28), color.opacity(0.02)]),
            startPoint: CGPoint(x: 0, y: rect.minY),
            endPoint: CGPoint(x: 0, y: rect.maxY)))
        ctx.stroke(line, with: .color(color),
                   style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
    }

    /// Index segments take their color from the mean value on the hydro ramp;
    /// gauge segments have no 0–100 meaning, so they use the app's calm tone.
    private func tint(for segment: TrendSegment) -> Color {
        guard showsSeverityBands, !segment.points.isEmpty else { return Hydro.rampColor(20) }
        let mean = segment.points.reduce(0) { $0 + $1.value } / Double(segment.points.count)
        return Hydro.rampColor(mean)
    }
}

#Preview {
    let end = Date()
    let start = end.addingTimeInterval(-30 * 86_400)
    let points = (0..<300).map { i -> TrendPoint in
        let t = Double(i) / 300
        return TrendPoint(date: start.addingTimeInterval(t * 30 * 86_400),
                          value: 40 + sin(t * 6) * 18 + t * 12)
    }
    return TrendChart(
        series: .make(from: points, window: start...end, gapThreshold: 21_600,
                      maxPoints: 31, yScale: .fixed(0...100), unit: ""),
        showsSeverityBands: true)
        .frame(width: 284, height: 120)
        .padding()
}
```

- [ ] **Step 2: Build**

```bash
swift build 2>&1 | tail -5
```

Expected: `Build complete`.

- [ ] **Step 3: Commit**

```bash
git add Sources/TiefstandUI/TrendChart.swift
git commit -m "feat(ui): Canvas trend chart with severity bands

Draws each TrendSegment as its own path, so recording gaps stay visible
instead of being interpolated over.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: `HistoryView`, `HistoryModel` and the header button

Wires everything into the popover.

**Files:**
- Create: `Sources/Tiefstand/HistoryView.swift`
- Modify: `Sources/Tiefstand/PopoverView.swift` (from Task 1)

**Interfaces:**
- Consumes: `TrendSeries`, `TrendPoint`, `YScale` (Task 4); `PEGELONLINEHistoryProvider`, `GaugeHistoryProviding`, `GaugeStation`, `GaugeMeasurement.trendPoint` (Task 5); `GaugeMatch`, `GaugeMatcher` (Task 6); `TrendChart` (Task 7); `IndexHistoryStore`, `IndexHistoryStoring` (Task 2); `StationReading` (existing — `name`, `coordinate`).
- Produces: `HistoryModel` (`@MainActor`, `ObservableObject`), `HistoryView(model:station:onBack:)`.

- [ ] **Step 1: Write `HistoryView.swift`**

```swift
import SwiftUI
import TiefstandCore
import TiefstandUI

/// Owns the history screen's state: which series, which window, the fetched
/// gauge curve and its cache.
///
/// Gauge history is fetched **only** in response to a user action — opening
/// the screen or switching tab/window. The README promises the app polls at
/// most every two hours, and that stays true only as long as nothing here
/// runs on a timer.
@MainActor
final class HistoryModel: ObservableObject {

    enum Series: String, CaseIterable, Identifiable {
        case gauge, index
        var id: String { rawValue }
        var label: String { self == .gauge ? "Gauge" : "Index" }
    }

    enum Window: String, CaseIterable, Identifiable {
        case week, month
        var id: String { rawValue }
        var label: String { self == .week ? "7 d" : "30 d" }
        var days: Int { self == .week ? 7 : 30 }
        /// 160 points for a week; 31 for a month, which is one bucket per day.
        var maxPoints: Int { self == .week ? 160 : 31 }
    }

    /// 3× the 2 h poll interval — anything longer is a real recording gap.
    static let indexGapThreshold: TimeInterval = 21_600
    /// 12× PEGELONLINE's 15-minute cadence; their occasional dropouts should
    /// read as dropouts.
    static let gaugeGapThreshold: TimeInterval = 10_800

    /// Gauge first: it has 30 days of real data on the very first open, while
    /// the index has only what this Mac has recorded so far.
    @Published var series: Series = .gauge
    @Published var window: Window = .month
    @Published private(set) var isLoading = false
    @Published private(set) var errorText: String?
    @Published private(set) var match: GaugeMatch?
    @Published private(set) var noGaugeNearby = false

    private let historyStore: IndexHistoryStoring
    private let gauges: GaugeHistoryProviding

    private struct CacheKey: Hashable { let uuid: String; let days: Int }
    private var measurementCache: [CacheKey: (fetchedAt: Date, points: [TrendPoint])] = [:]
    private var gaugePoints: [TrendPoint] = []
    private static let cacheLifetime: TimeInterval = 3_600

    init(historyStore: IndexHistoryStoring = IndexHistoryStore(),
         gauges: GaugeHistoryProviding = PEGELONLINEHistoryProvider()) {
        self.historyStore = historyStore
        self.gauges = gauges
    }

    // MARK: series

    /// Named `range(forDays:)` rather than `window(...)` on purpose — `window`
    /// is already the published property, and overloading the name here reads
    /// as ambiguous at every call site.
    private func range(forDays days: Int) -> ClosedRange<Date> {
        let end = Date()
        return end.addingTimeInterval(-Double(days) * 86_400)...end
    }

    var indexSeries: TrendSeries {
        let points = historyStore.load().map { TrendPoint(date: $0.timestamp, value: $0.index) }
        return .make(from: points,
                     window: range(forDays: window.days),
                     gapThreshold: Self.indexGapThreshold,
                     maxPoints: window.maxPoints,
                     yScale: .fixed(0...100),
                     unit: "")
    }

    var gaugeSeries: TrendSeries {
        .make(from: gaugePoints,
              window: range(forDays: window.days),
              gapThreshold: Self.gaugeGapThreshold,
              maxPoints: window.maxPoints,
              yScale: .auto,
              unit: "cm")
    }

    var currentSeries: TrendSeries { series == .index ? indexSeries : gaugeSeries }

    /// "recording since 3 Aug · 12 of 30 days", or the gauge's provenance.
    var caption: String {
        switch series {
        case .index:
            let samples = historyStore.load()
            guard let first = samples.first else { return "No samples recorded yet" }
            let covered = Int((indexSeries.coverage * Double(window.days)).rounded())
            let since = first.timestamp.formatted(.dateTime.day().month(.abbreviated))
            return "Recording since \(since) · \(covered) of \(window.days) days"
        case .gauge:
            guard let match else { return "" }
            if match.isExact { return match.station.displayName }
            let km = (match.distanceMeters / 1_000).rounded()
            return "\(match.station.displayName) · nearest gauge, \(Int(km)) km"
        }
    }

    // MARK: loading

    /// Called when the screen appears and whenever tab or window changes.
    func load(for station: StationReading?) async {
        guard series == .gauge else { return }   // the index comes off disk
        guard let station else {
            noGaugeNearby = true
            return
        }

        isLoading = true
        errorText = nil
        defer { isLoading = false }

        do {
            let match = self.match ?? GaugeMatcher.nearest(
                to: station.coordinate, in: try await gauges.stations())

            guard let match else {
                noGaugeNearby = true
                gaugePoints = []
                return
            }
            self.match = match
            noGaugeNearby = false

            let key = CacheKey(uuid: match.station.uuid, days: window.days)
            if let cached = measurementCache[key],
               Date().timeIntervalSince(cached.fetchedAt) < Self.cacheLifetime {
                gaugePoints = cached.points
                return
            }

            let points = try await gauges
                .measurements(uuid: match.station.uuid, days: window.days)
                .map(\.trendPoint)
            measurementCache[key] = (Date(), points)
            gaugePoints = points
        } catch {
            // Keep whatever curve is already on screen; only say what failed.
            errorText = error.localizedDescription
        }
    }
}

/// The history screen. Replaces the popover's contents in place, same 320 pt
/// width, fixed height so opening it doesn't make the popover jump.
struct HistoryView: View {
    @ObservedObject var model: HistoryModel
    let station: StationReading?
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            chart
            windowPicker
            seriesPicker
        }
        .task(id: taskKey) { await model.load(for: station) }
        // Esc goes back, matching the chevron. `.keyboardShortcut` needs a
        // focusable control, so the shortcut rides on a zero-size hidden button
        // rather than on the view itself.
        .background {
            Button("", action: onBack)
                .keyboardShortcut(.escape, modifiers: [])
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }

    /// Re-runs the load whenever the tab or window changes — and only then.
    private var taskKey: String { "\(model.series.rawValue)-\(model.window.rawValue)" }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Image(systemName: "chevron.left").font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .help("Back")

            Text(model.series == .index ? "Dryness Index" : "Water level")
                .font(.subheadline).fontWeight(.medium)
            Spacer()
            if model.isLoading { ProgressView().controlSize(.small) }
        }
    }

    @ViewBuilder
    private var chart: some View {
        ZStack {
            if model.series == .gauge && model.noGaugeNearby {
                message("No gauge history near \(station?.name ?? "this station")")
            } else if model.currentSeries.isEmpty {
                message(model.series == .index
                        ? "Recording started today — the curve appears after the next update"
                        : "No readings for this window")
            } else {
                TrendChart(series: model.currentSeries,
                           showsSeverityBands: model.series == .index)
            }
        }
        .frame(height: 132)

        Text(model.errorText ?? model.caption)
            .font(.caption2)
            .foregroundStyle(model.errorText == nil ? Color.secondary : Color.red)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
    }

    private var windowPicker: some View {
        HStack(spacing: 6) {
            ForEach(HistoryModel.Window.allCases) { option in
                Button(option.label) { model.window = option }
                    .buttonStyle(.borderless)
                    .font(.caption2.weight(model.window == option ? .bold : .regular))
                    .foregroundStyle(model.window == option ? Color.primary : Color.secondary)
            }
            Spacer()
        }
    }

    private var seriesPicker: some View {
        Picker("", selection: $model.series) {
            ForEach(HistoryModel.Series.allCases) { option in
                Text(option.label).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}
```

- [ ] **Step 2: Make the popover header open the history screen**

In `Sources/Tiefstand/PopoverView.swift`, add two state properties to `PopoverView`:

```swift
    @StateObject private var history = HistoryModel()
    @State private var showingHistory = false
    @State private var headerHovering = false
```

Replace the `body` with:

```swift
    var body: some View {
        Group {
            if showingHistory {
                HistoryView(model: history,
                            station: model.localStation,
                            onBack: { showingHistory = false })
            } else {
                dashboard
            }
        }
        .padding(18)
        .background(background)
        .animation(.easeInOut(duration: 0.18), value: showingHistory)
    }

    private var dashboard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button { showingHistory = true } label: { header }
                .buttonStyle(.plain)
                .background(.quaternary.opacity(headerHovering ? 0.4 : 0),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onHover { inside in
                    headerHovering = inside
                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            if let d = model.discharge, let g = model.groundwater {
                categorySection(discharge: d, groundwater: g)
            } else if model.isLoading {
                loading
            }
            if let station = model.localStation {
                LocalStationCard(station: station)
            }
            footer
        }
        .task { await model.refresh() }
    }
```

The existing `header`, `categorySection`, `loading`, `footer` and `background` members stay exactly as they are.

- [ ] **Step 3: Show the affordance on hover**

In the existing `header` property, replace the trailing `VStack` block

```swift
                Text("Germany").font(.caption2).foregroundStyle(.tertiary)
```

with

```swift
                Text("Germany").font(.caption2).foregroundStyle(.tertiary)
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .opacity(headerHovering ? 1 : 0)
```

and change the `.help(...)` text on `header` to:

```swift
        .help("National Dryness Index (0–100): the mean of the discharge and groundwater severity scores. Higher means drier. Click for the 7- and 30-day trend.")
```

- [ ] **Step 4: Build**

```bash
swift build 2>&1 | tail -5
```

Expected: `Build complete`.

- [ ] **Step 5: Run and walk the states**

```bash
./Scripts/make-app.sh --run
```

Check each, in order:
1. Popover opens on the dashboard as before.
2. Hovering the big number lifts the background and reveals the chart glyph; the cursor becomes a pointing hand.
3. Clicking it switches to the history screen with the **Gauge** tab selected and a **30 d** curve of real data.
4. `7 d` reloads with a denser curve.
5. Moving the cursor across the chart shows a dashed crosshair, a dot on the curve, and a date-and-value readout; leaving clears it.
6. The y-axis shows three values on the right edge and four dates below; on the Index tab the four severity bands are visible behind the curve.
7. Switching to **Index** shows either a short curve or "Recording started today…", plus a "Recording since …" caption.
8. The chevron returns to the dashboard. So does `Esc`.
9. Reopening the popover and clicking again within the hour issues no new network request — confirm with Console.app filtered on the process, or simply that the curve appears instantly.

- [ ] **Step 6: Run the suite and commit**

```bash
swift test 2>&1 | tail -5
git add Sources/Tiefstand/HistoryView.swift Sources/Tiefstand/PopoverView.swift
git commit -m "feat(app): history screen behind the headline number

In-place toggle in the popover: Gauge (PEGELONLINE, 30 days of real data)
and Index (self-recorded). Fetches only on user action, cached for an hour.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

Expected: still `Executed 50 tests, with 0 failures`.

---

### Task 9: Documentation and screenshots

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: `docs/preview.png` (add `docs/history.png`)

**Interfaces:**
- Consumes: the shipped feature.
- Produces: nothing code-facing.

- [ ] **Step 1: Update the README's feature list**

Under "What it does", after the "Popover dashboard" bullet, add:

```markdown
- **History:** click the index to switch to a **7- or 30-day trend** — the national
  index and your local gauge, on one chart.
```

- [ ] **Step 2: Update the README's data-source note**

In the "Well-behaved client" paragraph, replace the sentence beginning "Nothing is mirrored" with:

```markdown
Gauge history comes from PEGELONLINE's `measurements.json`, which serves a rolling
30-day window — fetched **only when you open the history view**, never on a timer, and
cached for an hour. The gauge list is cached on disk for 30 days. The Dryness Index has
no upstream history (NIWIS publishes the current aggregate only), so the app records its
own samples locally; nothing is mirrored or redistributed.
```

- [ ] **Step 3: Capture the history screenshot**

Per the project's screenshot practice, hide other apps first so no icons bleed into the shot, and open the popover and capture in one step:

```bash
osascript -e 'tell application "System Events" to set visible of every process whose visible is true and name is not "Tiefstand" to false'
```

Then open the popover, click through to the history view with the Gauge tab on 30 d, and — because the popover closes as soon as focus moves — capture with a delay rather than interactively:

```bash
screencapture -T 8 -R 0,0,0,0 -x docs/history.png   # placeholder region
```

`-R` needs the popover's actual on-screen rectangle. Take one interactive shot first to find it (`screencapture -i -x /tmp/probe.png`, then `sips -g pixelWidth -g pixelHeight /tmp/probe.png`), or simply capture the full screen with a delay and crop:

```bash
screencapture -T 8 -x /tmp/full.png
sips -c 900 760 --cropOffset 40 60 /tmp/full.png --out docs/history.png
```

Adjust the crop numbers to the popover's position. Verify the result before committing: `open docs/history.png`.

- [ ] **Step 4: Embed the screenshot**

In `README.md`, after the existing `docs/preview.png` block, add:

```markdown
<p align="center">
  <img src="docs/history.png" width="340" alt="Tiefstand history view: 30-day gauge trend">
</p>
```

- [ ] **Step 5: Add the changelog entry**

At the top of `CHANGELOG.md`, above the existing entries:

```markdown
## Unreleased

### Added
- History view in the popover: 7- and 30-day trends for the national Dryness Index and
  the local gauge, reached by clicking the headline number.
- Index samples are recorded locally after every refresh (400-day retention) — NIWIS
  publishes no history for the aggregate the index is built from.
- Gauge history from PEGELONLINE, fetched on demand and cached for an hour.
```

- [ ] **Step 6: Commit**

```bash
git add README.md CHANGELOG.md docs/history.png
git commit -m "docs: document the history view and its data policy

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

## Verification

After Task 9:

```bash
swift test 2>&1 | tail -5          # expect 50 tests, 0 failures
swift build 2>&1 | tail -3         # expect Build complete
./Scripts/make-app.sh --run        # walk the seven checks from Task 8, Step 5
git log --oneline -9               # expect one commit per task
```
