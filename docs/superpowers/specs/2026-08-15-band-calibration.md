# Calibrating the Dryness Level bands

**Date:** 2026-08-15
**Outcome:** thresholds changed from 25 / 50 / 75 to **27 / 38 / 52**
**Code:** `Sources/TiefstandCore/DrynessLevel.swift`

---

## The problem

`DrynessLevel` split 0–100 into four equal bands. Nobody had ever checked what
range the index actually occupies.

It turns out the index cannot reach its own top band. The Dryness Index is the
mean of two severity scores, each itself a mean of four-level classifications
across hundreds of gauges. Means over a skewed distribution do not use their
upper range: even when half the country's rivers sit in the worst class, the
average lands nowhere near 100.

On the day this was investigated the index read **62 — "High"**, the third of
four bands, while the median German discharge gauge was classified *extremely
low* and 175 of 357 gauges were in the worst class. That is an understatement
reported by the app's most prominent element.

## Getting the data

NIWIS publishes only the current aggregate, so there was nothing to calibrate
against — until the portal's own charting endpoint was reverse-engineered:

```
GET /api/infodiagramm/diagrammErgebnis
    ?messgroesse=ABFLUSS|GRUNDWASSER
    &diagrammart=ZEITREIHE
    &messstelleNr={station}
    &klassifikationsAnzeige=DYNAMISCH
    &von=2000-01-01&bis=2026-08-15
```

It is strict — omit any parameter and it answers `400` naming the one it wants,
which is how the shape was found — and it returns two things that matter:

- `zeitreihen[0].werte` — the station's **daily measurements**, back to 1991.
- `flaechen` — the **class boundaries**, one daily curve per class ("niedrig",
  "sehr niedrig", "extrem niedrig"), in the same unit as the measurement.

The boundaries are the unlock. The README notes that NIWIS classifies each
station by percentile thresholds against the 1991–2020 WMO reference period and
that the exact boundaries are not published. They are not published as a table,
but they come back with every chart request. Measurement plus boundary means
every station's class is reconstructible for every past day, and from that the
national index.

## Method

25 discharge stations and 25 groundwater stations, evenly sampled from the
station lists, 2000-01-01 to 2026-08-15. For each station and day, the class is
`3` if the value is at or below the "extrem niedrig" bound, `2` at or below
"sehr niedrig", `1` at or below "niedrig", else `0` — then averaged across
stations and scaled to 0–100, exactly as `DomainAggregate.severityScore` does.
The index is the mean of the two domain scores on days where both exist.

- Discharge: 9,722 days.
- Groundwater: 2,560 days — groundwater is measured roughly weekly, not daily,
  and the index can only be reconstructed where both domains have a reading.
- ~150 MB fetched in one throttled pass. **Not repeatable behaviour for the
  app**, which is why nothing about this ships as runtime code.

### Validation

| | Reconstruction | NIWIS live |
|---|---|---|
| Discharge score, 13 Aug 2026 | 72 | 71 |
| Index, 10 Aug 2026 | 59 | 62 (15 Aug) |

A 25-station sample tracks the full 357-station aggregate to within a few
points. Good enough to set band edges; not good enough to argue over one.

## Result

Yearly maxima of the reconstructed national index, 2000–2026:

```
2018 ██████████████████ 60      2003 ███████████ 37
2022 ████████████████████ 64    2015 ██████████ 35
2026 ██████████████████ 59      2017 ██████████ 35
2020 ████████████████ 52        2006 ██████████ 34
2025 ████████████████ 52        2011 █████████ 31
2019 ██████████████ 47          2013 ███ 10
2014 █████████████ 44           2024 ███ 11
```

**Maximum over twenty-seven years: 64.** The old `severe` threshold of 75 was
never reached, and could not have been.

## The thresholds

The 75th, 90th and 98th percentiles of the reconstruction — **27 / 38 / 52** —
give time shares of roughly 75 % normal, 15 % elevated, 8 % high, 2 % severe.

They were chosen against a criterion that can be argued with rather than only
computed: **the droughts people remember must register, and ordinary years must
not.** At 52, `severe` covers 2018, 2022, 2025 and 2026 — the two canonical
German drought summers plus the ongoing one — and excludes wet years such as
2013 and 2024, which peaked at 10 and 11.

Today's index of 62 reads **Severe**. It previously read *High*.

## Caveats

1. **A sample, not a census.** 25 of 357 discharge and 25 of 287 groundwater
   stations. Validated to within a few points on the current value; not
   guaranteed across all conditions.
2. **Mildly circular.** The window used to derive percentiles contains the
   droughts being classified. The drought-year criterion is the primary check
   for exactly that reason; the percentiles set the lower edges, where the
   circularity does not bite.
3. **2003 sits below the line** (peak 37 → `high`). It is remembered as a
   drought year, and in air temperature it was — but its hydrological
   low-water signature was milder than 2018 and 2022, which is consistent with
   the hydrological literature. Recorded here so the omission is a known one.
4. **Groundwater coverage is thin** — weekly measurements mean the index is
   reconstructible on 2,560 of ~9,700 days.
5. ~~**The colour ramp was not recalibrated.**~~ **Resolved 2026-08-15.** The
   ramp had the same flaw as the bands: `index / 100` spent its top third on
   values that never occur, so at 62 the number read amber while its pill said
   "Severe". `Hydro.rampColor` now maps through
   `DrynessLevel.severityFraction`, anchored at the band edges
   (0 → 0, 27 → 0.33, 38 → 0.60, 52 → 0.85, 64 → 1.0, saturating above), so
   colour and label change together by construction. Equal steps in the index
   deliberately do not give equal steps in colour: 10 → 20 is weather, 50 → 60
   is a national event. `DrynessLevel.color` resamples at the band midpoints
   (13/32/45/58); the old points 62 and 88 are both fully red under the new
   ramp and the two worst pills would have collapsed to one colour.

## Reproducing

The analysis scripts were throwaway and are not in the repo — deliberately, as
running them again means another ~150 MB against a public agency's API. The
endpoint shape above and the method described here are enough to rebuild them.
`NIWISProvider.stationSeriesURL` is the same call, used at one station at a
time for the gauge history view.
