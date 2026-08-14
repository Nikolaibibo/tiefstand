# Design: History graph in the popover

**Date:** 2026-08-15
**Status:** Approved, ready for implementation planning
**Scope:** A second screen in the menu-bar popover that plots the last 7 or 30 days —
the national Dryness Index and the local gauge — reached by clicking the headline number.

---

## 1. Problem

`IndexModel` holds exactly one snapshot (`index`, `discharge`, `groundwater`,
`localStation`, `updatedAt`). Every refresh overwrites the previous values. The app can
answer "how dry is Germany right now" but not "is it getting worse", which is the
question a low-water indicator naturally raises.

The goal: a prominent click in the popover switches to a graph view showing the trend
over the last week or month.

## 2. Data availability

Probed live on 2026-08-14. This section is the load-bearing part of the design — the two
series have opposite data characteristics, and that shapes everything downstream.

### PEGELONLINE — real history, immediate

`GET https://www.pegelonline.wsv.de/webservices/rest-api/v2/stations/{uuid}/W/measurements.json?start=P30D`

Verified against station CELLE (`b475386c-30cc-453a-b3b7-1d17ace13595`): **2,880 points**
at 15-minute resolution covering 2026-07-15 to 2026-08-14, 213 KB, no auth. Response
shape: `[{"timestamp": "2026-07-15T15:45:00+02:00", "value": 135.0}]`.

`GET .../v2/stations.json` returns the full gauge list (262 KB) with `uuid`, `longitude`,
`latitude`, `shortname`, `longname`, `water.shortname`.

PEGELONLINE keeps a **rolling 30-day window** of measurements. That is the hard ceiling
for this series; no longer window is obtainable.

### NIWIS — current state only

`GET https://niwis-online.de/api/kreisdiagramme/{PARAM}` returns the current national
aggregate and nothing else. Guessed history paths (`ganglinie`, `zeitreihe`, `verlauf`,
`historie`) all return 404.

The portal's Angular bundle does contain timeseries machinery — `/zeitreihendiagramm-
konfiguration`, `/diagrammErgebnis`, `/auftretensdiagramm`, and enum values such as
`ZEITREIHE_VARIABEL_TAGESWERTE_NUMBER` — so NIWIS *can* serve time series. The call shape
is not reverse-engineered (the endpoints are POST-with-config, built inside lazy-loaded
chunks). See §12, risk 4: this is the upgrade path that would one day give the index real
backfill.

Also noted: the NIWIS map supports a `darstellungsmodus` of `ENTWICKLUNG_LETZTE_7_TAGE`,
so a 7-day per-station development exists in the source — but not on the endpoints this
app uses.

### Consequence

The Dryness Index is this app's own construction from the NIWIS aggregate. **No source
anywhere holds its history.** To plot it, Tiefstand must record its own samples. The index
curve therefore starts empty and fills over time, while the gauge curve is complete on
first click.

| | Index | Gauge |
|---|---|---|
| Origin | recorded by us | fetched on demand |
| Backfill | none — starts at first run | 30 days, immediate |
| Resolution | 1 point / 2 h (poll interval) | 1 point / 15 min |
| Gaps | yes — Mac asleep, app quit | none |
| Y axis | fixed 0–100 | centimetres, auto-scaled |

## 3. Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Which series | **Both** | The gauge guarantees a non-empty first impression; the index accrues from day one instead of being deferred forever. |
| Presentation | **In-place toggle** in the 320 pt popover | Smallest change, no window lifecycle in an `LSUIElement` app, feels native. |
| Gauge identity | ~~Match, else nearest, else nothing~~ → **fixed reference gauge (Kaub · Rhein)** | Revised 2026-08-15 after measurement: matching leaves the tab empty for 80 % of the stations the app actually shows (§12, risk 1). NIWIS and PEGELONLINE share no IDs (§5), and PEGELONLINE covers federal waterways only. Kaub guarantees a full curve and is the country's reference gauge for low water. |
| Time windows | **7 d · 30 d** | What was asked for, and PEGELONLINE's ceiling. Low water moves slowly; finer windows would add buttons without adding information. |
| Chart | **Custom `Canvas`** | ~120 lines, matches `WaveGauge`/`Donut`, full control over the `DrynessLevel` bands. Swift Charts would need heavy restyling to fit `Hydro` and brings its own layout opinions into a 320 pt popover. |
| Index storage | **Append-only JSON** in Application Support | Keeps `TiefstandCore` Foundation-only and unit-testable, following the pattern `WidgetRefresh.swift` already sets. SwiftData/SQLite is overkill for ~4,400 rows. |
| Retention | **400 days** | Only 7/30 d are displayed, but discarded samples are unrecoverable. 12 samples/day × 400 days ≈ 200 KB. In a year the data for an annual view simply exists. |

**Verified non-constraint:** the `Canvas`-does-not-render note from the v0.1.0 work
applies to the **`MenuBarExtra` label only**. Inside the popover `Canvas` works —
`Donut` (`Views.swift:301`) has used it since the first release.

## 4. Architecture

Two sources, one chart. `TrendSeries` is the interface between them; the chart never
learns where its points came from.

```
NIWIS aggregate ──► IndexModel.refresh() ──► IndexHistoryStore  ──┐
  (every 2 h)          (existing)             append/prune/load   │
                                                                  ├─► TrendSeries ─► TrendChart
PEGELONLINE      ──► GaugeHistoryProvider ──► [Measurement]     ──┘   (pure)         (Canvas)
  (on click)          + GaugeMatcher
```

### Components

**`DrynessSample`** (Core, new) — one recorded observation.

```swift
public struct DrynessSample: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let index: Double
    public let dischargeScore: Double?
    public let groundwaterScore: Double?
}
```

Both domain scores are stored even though only the combined index is plotted, so
per-domain curves can be added later without a gap in the record.

**`IndexHistoryStore`** (Core, new) — durable append-only log.

```swift
public protocol IndexHistoryStoring: Sendable {
    func append(_ sample: DrynessSample) throws
    func load() throws -> [DrynessSample]
}

public struct IndexHistoryStore: IndexHistoryStoring {
    public init(fileURL: URL = IndexHistoryStore.defaultURL,
                retention: TimeInterval = 400 * 86_400)
}
```

- Location: `~/Library/Application Support/Tiefstand/index-history.json`. The app is
  non-sandboxed (ad-hoc signed, `LSUIElement`), so the path is directly usable.
- `append` loads, appends, prunes older than `retention`, writes atomically
  (`Data.write(to:options:.atomic)`). At ~4,400 entries a full rewrite every two hours is
  negligible.
- A missing file yields an empty history. **A corrupt or undecodable file also yields an
  empty history rather than throwing** — a broken log must never prevent the app from
  starting or refreshing. The bad file is moved aside to `index-history.corrupt.json`
  once, so the failure is inspectable instead of silent.

**`TrendSeries`** (Core, new) — the pure transformation from raw samples to drawable
geometry. This is where all the interesting logic lives, and it is fully testable without
a UI.

```swift
public struct TrendPoint: Equatable, Sendable { public let date: Date; public let value: Double }
public struct TrendSegment: Equatable, Sendable { public let points: [TrendPoint] }

public enum YScale: Equatable, Sendable { case fixed(ClosedRange<Double>); case auto }

public struct TrendSeries: Equatable, Sendable {
    public let segments: [TrendSegment]      // contiguous runs; a gap starts a new segment
    public let window: ClosedRange<Date>
    public let yScale: YScale
    public let unit: String                  // "" for the index, "cm" for the gauge
    public let coverage: Double              // 0…1, fraction of the window actually covered
}
```

Construction is one pure function:

```swift
public extension TrendSeries {
    static func make(from points: [TrendPoint],
                     window: ClosedRange<Date>,
                     gapThreshold: TimeInterval,
                     maxPoints: Int,
                     yScale: YScale,
                     unit: String) -> TrendSeries
}
```

Behaviour:
1. **Filter** to `window`.
2. **Downsample** to at most `maxPoints` by time-bucket averaging. Buckets are aligned to
   the window start so the result is stable across refreshes, and the first and last
   input timestamps are preserved as bucket boundaries so the curve doesn't visually
   shrink. The caller picks `maxPoints`: **160** for a 7-day window (roughly hourly for
   the gauge), **31** for a 30-day window — which is exactly one bucket per day.
3. **Split** on gaps: any interval between consecutive points longer than `gapThreshold`
   ends the current segment and starts a new one. The chart draws segments as separate
   paths, so a three-day outage reads as a break rather than a straight line through
   invented data.
   - Index: `gapThreshold` = 6 h (3× the 2 h poll cadence).
   - Gauge: `gapThreshold` = 3 h (12× the 15 min cadence) — PEGELONLINE has occasional
     dropouts and they should read as dropouts.
4. **Coverage** = covered time ÷ window length, used for the "n of 30 days" label.

Daily bucketing uses the **mean**, not the minimum. The screen answers "which way is this
going", and a mean is the honest summary of that. A daily min/max band is a plausible
later addition and is deliberately not built now.

**`GaugeHistoryProvider`** (Core, new) — PEGELONLINE access.

```swift
public struct GaugeMeasurement: Decodable, Equatable, Sendable {
    public let timestamp: Date
    public let value: Double
}

public protocol GaugeHistoryProviding: Sendable {
    func stations() async throws -> [GaugeStation]
    func measurements(uuid: String, days: Int) async throws -> [GaugeMeasurement]
}
```

- `stations()` fetches `stations.json` and caches it on disk for 30 days — the gauge list
  is near-static and 262 KB should be fetched roughly never.
- `measurements(uuid:days:)` requests `?start=P7D` or `?start=P30D`, so the 7-day view
  transfers ~50 KB instead of 213 KB.
- Timestamps are ISO-8601 with offsets; decoding uses `.iso8601` with fractional seconds
  disabled, matching the observed format.
- The same identifying `User-Agent` as `NIWISProvider` is sent, for the same reason.

**`GaugeMatcher`** (Core, new) — the bridge between the two ID worlds.

```swift
public struct GaugeMatch: Equatable, Sendable {
    public let station: GaugeStation
    public let distanceMeters: Double
    public var isExact: Bool { distanceMeters <= 2_000 }
}

public enum GaugeMatcher {
    public static let exactToleranceMeters = 2_000.0
    public static let maximumDistanceMeters = 25_000.0
    public static func nearest(to coordinate: Coordinate,
                               in stations: [GaugeStation]) -> GaugeMatch?
}
```

Haversine distance against every gauge; the nearest wins. Beyond
`maximumDistanceMeters` the function returns `nil` — a gauge 80 km away on a different
river is not "this station's history", and showing it would be a quiet lie. The 25 km
ceiling is the difference between a useful fallback and a misleading one.

**`TrendChart`** (TiefstandUI, new) — `Canvas`-based renderer for a `TrendSeries`.

- Line stroked with `Hydro.gradient`, soft area fill beneath at ~0.18 opacity.
- Index only: the four `DrynessLevel` bands (0–25–50–75–100) as faint horizontal bands
  behind the curve, so a value can be read qualitatively without an axis lookup.
- Three y-axis ticks, three to four x-axis date ticks, `.caption2`/`.tertiary` to match
  the existing popover typography.
- Hover (`.onContinuousHover`) shows a crosshair with date and value; leaving restores
  the summary line.
- Segments drawn as separate paths — gaps are visible by construction.

## 5. Why the gauge needs a bridge at all

> [!contradiction] Gauge identity
> **Design (14.08.):** match the NIWIS `localStation` to a PEGELONLINE gauge by coordinate.
> **Measurement (15.08.):** 80 % of the driest NIWIS stations have no federal gauge within
> 25 km → the tab would be empty most of the time (§12, risk 1).
> → Resolved: the tab plots **Kaub · Rhein**, a fixed reference gauge. The matching design
> below is kept because it is the CoreLocation path, and because it explains why the
> obvious approach doesn't work.

NIWIS station IDs look like `DESM_DEBY16607001`; PEGELONLINE uses UUIDs such as
`b475386c-30cc-453a-b3b7-1d17ace13595`. There is no crosswalk, and NIWIS coordinates
arrive as `{"x": lon, "y": lat}` (already modelled by `Coordinate`). Matching therefore
happens geographically:

| Distance | Behaviour | Label |
|---|---|---|
| ≤ 2 km | treated as the same gauge | station name only |
| 2–25 km | nearest gauge, disclosed | "nearest gauge · 6 km" |
| > 25 km | no series | "no gauge history near this station" |

**Naming caveat.** `IndexModel.localStation` is currently *the driest discharge gauge in
Germany*, not a nearby one — CoreLocation is still a TODO (`TiefstandApp.swift:86`). The
tab is therefore labelled **"Gauge"**, not "Local gauge". With the reference-gauge decision
the caption names the station outright ("KAUB · RHEIN"), so nothing in the UI claims the
curve is local. When CoreLocation lands, `GaugeMatcher` supplies the user's nearest gauge
and Kaub becomes the fallback for a denied or unavailable location.

## 6. Interaction

```
┌─ popover ───────────────┐        ┌─ history ────────────────┐
│  ((~))  47   HIGH       │  tap   │ ‹   47 · 30 d            │
│                         │ ─────► │ ╭──────────────────────╮ │
│  BY CATEGORY            │        │ │      ╱‾╲             │ │
│  ◕ 44        ◕ 50       │        │ │  ╱‾╲╱   ╲___         │ │
│                         │  ‹     │ ╰──────────────────────╯ │
│  CELLE        114 cm    │ ◄───── │  7 d · 30 d              │
│  NIWIS …        15:38   │        │  [ Gauge | Index ]       │
└─────────────────────────┘        └──────────────────────────┘
            320 pt                            320 pt
```

- The header (gauge + number + level pill) becomes a `.plain` `Button` with the same
  hover treatment `LocalStationCard` already uses — pointing-hand cursor, subtle
  background lift, a small chart glyph appearing on hover. The affordance vocabulary is
  already established in this file; reuse it rather than inventing a new one.
- Back is a `chevron.left` at the top left. `Esc` also returns.
- Transition: crossfade. The popover width stays 320 pt; the history screen is a fixed
  ~300 pt tall so opening it doesn't make the popover jump.
- **Gauge is the default tab** on first open, so the first thing seen is a complete
  curve rather than a nearly empty index. The selected tab and window then persist for
  the app's lifetime (in-memory), not across launches. Nothing is written to
  `UserDefaults` for this.
- The station card keeps its current behaviour (opens the NIWIS map). It is *not*
  rerouted into the history view.

## 7. Loading, empty and error states

| Condition | Screen |
|---|---|
| Gauge tab, fetch in flight | `ProgressView` at the chart's size — no layout jump |
| Gauge tab, reference gauge missing from the station list | "Reference gauge unavailable" — should never happen; Kaub is a permanent federal gauge |
| Gauge tab, request failed | Inline message in the existing footer style + a retry button; the last successful series stays on screen if there is one |
| Index tab, coverage < 100 % | Chart of what exists, plus "recording since 15 Aug · 2 of 30 days" |
| Index tab, fewer than 2 samples | "Recording started today — the curve appears after the next update" |

The index empty state is deliberately explicit about *why* it is empty. An unexplained
blank chart reads as a bug; "recording since" reads as a design.

## 8. Polite client behaviour

The README states the app "polls at most every two hours". That claim has to survive this
feature, so:

- Gauge history is fetched **only on user action** (opening the tab, switching window),
  never on a timer.
- Results are cached in memory per `(uuid, window)` for 60 minutes; re-opening the
  popover within that hour costs no request.
- `stations.json` is cached on disk for 30 days.
- Every request carries `NIWISProvider.userAgent`.
- The index series generates **no** network traffic at all — it is read from disk.

The README's data-source section gains a paragraph describing the PEGELONLINE history
call and this on-demand policy, so the documented behaviour matches the shipped one.

## 9. File map

**New — `Sources/TiefstandCore/`** (pure Foundation, TDD)
- `DrynessSample.swift`
- `IndexHistoryStore.swift`
- `TrendSeries.swift`
- `GaugeHistory.swift` — `GaugeStation`, `GaugeMeasurement`, `GaugeHistoryProvider`
- `GaugeMatcher.swift`

**New — `Sources/TiefstandUI/`**
- `TrendChart.swift`

**Refactor — `Sources/Tiefstand/Views.swift`** (384 lines, the largest file in the repo)
splits, as a pure move with no logic change, into:
- `MenuBarGlyph.swift` — `MenuBarLabel`, `MenuBarGlyph`, `WaveFillShape`, `WaveSurfaceLine`
- `PopoverView.swift` — `PopoverView`, `LoginItem`, shared helpers
- `Cards.swift` — `DomainCard`, `Donut`, `LocalStationCard`
- `HistoryView.swift` — new screen

Without the split this file reaches ~600 lines holding two full screens.

**Modified**
- `TiefstandApp.swift` — `IndexModel` appends a `DrynessSample` after each successful
  refresh; new `HistoryModel` owns tab/window state, the gauge fetch and its cache.
- `README.md` — data sources and polling policy.
- `CHANGELOG.md` — new entry.

## 10. Testing

XCTest via `swift test`, matching the existing 13-test suite. Core is fully covered; the
UI is not unit-tested, consistent with the repo today.

`IndexHistoryStore`
1. `append` then `load` returns the sample
2. Samples older than the retention window are pruned on append
3. A missing file loads as an empty history
4. A corrupt file loads as empty, is moved aside, and does not throw

`TrendSeries`
5. Points outside the window are excluded
6. 672 points in a 7-day window with `maxPoints: 160` downsample to ≤ 160 output points
7. 2,880 points in a 30-day window with `maxPoints: 31` bucket to ≤ 31 daily points
8. An interval beyond `gapThreshold` splits one segment into two
9. Contiguous points produce exactly one segment
10. `coverage` is 1.0 for a fully covered window and ~0.07 for two days of thirty

`GaugeHistory`
11. A recorded `measurements.json` fixture decodes to timestamps and values
12. An ISO-8601 timestamp with a `+02:00` offset decodes to the correct instant

`GaugeMatcher`
13. Haversine distance for a known coordinate pair is correct within 1 %
14. A gauge within 2 km reports `isExact == true`
15. A gauge at 2.1 km reports `isExact == false` but is still returned
16. The nearest gauge beyond 25 km returns `nil`

`DrynessSample`
17. Codable round-trip preserves all fields including `nil` domain scores

## 11. Out of scope

Deliberately excluded, to keep this one shippable change:

- Sparkline inside `LocalStationCard`
- History in the WidgetKit widget (the widget neither reads nor writes the store)
- Separate discharge and groundwater curves — the *samples* carry both values, so this
  is addable later with no gap in the record, but no UI is built for it now
- A one-year window — unfillable for either series today
- Daily min/max bands
- CSV/JSON export
- Reverse-engineering the NIWIS timeseries API (§12, risk 4)

## 12. Risks

1. ~~**Match rate is unknown.**~~ **Measured 2026-08-15 — the risk landed, and it sank the
   original plan for this tab.** Against 729 placeable PEGELONLINE gauges:

   | Population | ≤ 2 km | ≤ 25 km | no match |
   |---|---|---|---|
   | All 357 NIWIS discharge stations | 65 (18 %) | 117 (33 %) | **175 (49 %)** |
   | The 20 driest — i.e. what the app actually shows | — | 4 total | **16 (80 %)** |

   PEGELONLINE covers **federal waterways only**. The driest gauges are almost all small
   Bavarian rivers on state networks — Amper, Ammer, Strogen, Glonn, Traun, Salzach, Rott,
   Bibert, Aisch, Tauber — sitting 30–110 km from the nearest federal gauge. The premise
   that the gauge tab would always have real data was simply wrong.

   **Decision (2026-08-15): the gauge tab plots a fixed reference gauge — Kaub on the
   Rhine.** Kaub is Germany's canonical low-water bellwether, the gauge quoted in shipping
   and news reporting, and it serves a complete 30-day series (43 → 6 cm over the month
   measured). This keeps the tab's guarantee — a full curve on the very first open —
   without CoreLocation, station matching, or a permission dialogue. It is not "your"
   gauge, and the label says so.

   `GaugeMatcher` (§4) stays in the codebase, tested but currently unused: it is exactly
   what the CoreLocation roadmap item needs, and the numbers above are the reason it isn't
   wired to `localStation` today.
2. **The index curve is thin for weeks.** Accepted by design; the empty state names the
   reason. The gauge tab is the default on first open precisely so the first impression
   is a real curve.
3. **Sampling depends on the app running.** Poll cadence is 2 h, and a closed lid or a
   quit app produces gaps. Handled by drawing gaps rather than interpolating across them.
4. **NIWIS may already have what we are recording by hand.** The timeseries endpoints
   exist but were not decoded. If they turn out to serve daily national values, the index
   series could be backfilled and this store demoted to a cache. That would be a welcome
   change, not a rewrite — `TrendSeries` is the seam it would enter through.

## 13. Implementation sequence

1. Split `Views.swift` — pure move, no behaviour change, its own commit
2. `DrynessSample` + `IndexHistoryStore` (TDD)
3. Wire recording into `IndexModel.refresh()`
4. `TrendSeries` (TDD) — the largest piece of logic
5. `GaugeHistory` + `GaugeMatcher` (TDD)
6. `TrendChart`
7. `HistoryView` + `HistoryModel` + header button
8. README, CHANGELOG, refreshed screenshots
