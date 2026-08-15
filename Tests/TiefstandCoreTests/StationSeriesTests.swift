import XCTest
@testable import TiefstandCore

final class StationSeriesTests: XCTestCase {

    /// Trimmed from a live `diagrammErgebnis` response for Inkofen (Amper),
    /// captured 2026-08-15. `flaechen` carries the low-water class boundaries
    /// as one curve per class, in the same unit as the measurement — which is
    /// what lets them be drawn as overlays on the same axis.
    private let fixture = Data("""
    {
      "von": "2025-08-15",
      "bis": "2025-08-18",
      "ueberschrift": "Inkofen (Amper)",
      "referenzzeitraum": {"von": "1991-01-01", "bis": "2020-12-31"},
      "zeitreihen": [
        {"einheit": "m³/s", "label": "Abfluss", "werte": [
          {"messwert": 39.6, "datum": "2025-08-15"},
          {"messwert": null, "datum": "2025-08-16"},
          {"messwert": 47.5, "datum": "2025-08-17"},
          {"messwert": 12.0, "datum": "2025-08-18"}
        ]}
      ],
      "flaechen": [
        {"label": "extrem niedrig", "istUntenOffen": true, "einheit": "m³/s", "spannen": [
          {"datum": "2025-08-15T00:00:00", "untererWert": null, "obererWert": 17.6},
          {"datum": "2025-08-18T00:00:00", "untererWert": null, "obererWert": 17.4}
        ]},
        {"label": "sehr niedrig", "istUntenOffen": false, "einheit": "m³/s", "spannen": [
          {"datum": "2025-08-15T00:00:00", "untererWert": 17.6, "obererWert": 25.1}
        ]},
        {"label": "niedrig", "istUntenOffen": false, "einheit": "m³/s", "spannen": [
          {"datum": "2025-08-15T00:00:00", "untererWert": 25.1, "obererWert": 40.2}
        ]}
      ]
    }
    """.utf8)

    func test_decodesTheStationNameAndUnit() throws {
        let series = try StationSeries.decode(fixture)

        XCTAssertEqual(series.stationName, "Inkofen (Amper)")
        XCTAssertEqual(series.unit, "m³/s")
    }

    /// A `null` reading is a gap in the record, not a zero-flow river.
    func test_nullMeasurementsAreDroppedRatherThanZeroed() throws {
        let series = try StationSeries.decode(fixture)

        XCTAssertEqual(series.values.map(\.value), [39.6, 47.5, 12.0])
    }

    func test_valuesCarryTheirDates() throws {
        let series = try StationSeries.decode(fixture)
        let calendar = Calendar(identifier: .gregorian)

        let day = calendar.dateComponents(in: TimeZone(identifier: "Europe/Berlin")!,
                                          from: series.values[0].date).day
        XCTAssertEqual(day, 15)
    }

    /// The three boundaries arrive in arbitrary order and must come out
    /// ordered by severity, because the chart draws and labels them that way.
    func test_thresholdsComeOutOrderedFromMildestToMostSevere() throws {
        let series = try StationSeries.decode(fixture)

        XCTAssertEqual(series.thresholds.map(\.label), ["Low", "Very low", "Extremely low"])
    }

    func test_eachThresholdBecomesACurveOfItsUpperBound() throws {
        let series = try StationSeries.decode(fixture)
        let extreme = try XCTUnwrap(series.thresholds.last)

        XCTAssertEqual(extreme.label, "Extremely low")
        XCTAssertEqual(extreme.points.map(\.value), [17.6, 17.4])
    }

    func test_theReferencePeriodIsCarriedThrough() throws {
        let series = try StationSeries.decode(fixture)

        XCTAssertEqual(series.referencePeriod, "1991–2020")
    }

    func test_anEmptyResponseDecodesToAnEmptySeriesRatherThanThrowing() throws {
        let empty = Data("""
        {"von":"2025-01-01","bis":"2025-01-02","ueberschrift":"X",
         "zeitreihen":[],"flaechen":[]}
        """.utf8)

        let series = try StationSeries.decode(empty)

        XCTAssertTrue(series.values.isEmpty)
        XCTAssertTrue(series.thresholds.isEmpty)
        XCTAssertNil(series.referencePeriod)
    }

    // MARK: request

    func test_theRequestURLCarriesEveryParameterNIWISDemands() {
        let provider = NIWISProvider()

        let url = provider.stationSeriesURL(domain: .discharge,
                                            stationNumber: "DESM_DEBY16607001",
                                            from: "2024-01-01", to: "2026-08-15")

        let query = url.query ?? ""
        for expected in ["messgroesse=ABFLUSS", "diagrammart=ZEITREIHE",
                         "messstelleNr=DESM_DEBY16607001",
                         "klassifikationsAnzeige=DYNAMISCH",
                         "von=2024-01-01", "bis=2026-08-15"] {
            XCTAssertTrue(query.contains(expected), "missing \(expected) in \(query)")
        }
        XCTAssertTrue(url.path.hasSuffix("/infodiagramm/diagrammErgebnis"))
    }

    /// Omitting any one of them is a 400 with the parameter named — the API is
    /// strict, and this is how the shape was discovered in the first place.
    func test_groundwaterUsesItsOwnMeasurand() {
        let url = NIWISProvider().stationSeriesURL(domain: .groundwater,
                                                   stationNumber: "X",
                                                   from: "2024-01-01", to: "2026-08-15")

        XCTAssertTrue((url.query ?? "").contains("messgroesse=GRUNDWASSER"))
    }
}
