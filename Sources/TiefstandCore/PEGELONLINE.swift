import Foundation

/// Maps a PEGELONLINE `stations.json` response (with current measurements)
/// into a `DomainAggregate`. PEGELONLINE only classifies water level as
/// low / normal / high, so the fallback aggregate is coarse — it never
/// produces the very-low or extreme buckets that NIWIS does.
public enum PEGELONLINEMapper {
    public static func aggregate(from data: Data) throws -> DomainAggregate {
        let stations = try JSONDecoder().decode([Station].self, from: data)
        var kein = 0, niedrig = 0, keine = 0
        for station in stations {
            let state = station.timeseries
                .first { $0.shortname == "W" }?
                .currentMeasurement?.stateMnwMhw
            switch state {
            case "low":            niedrig += 1
            case "normal", "high": kein += 1
            default:               keine += 1
            }
        }
        return DomainAggregate(keinNiedrigwasser: kein, niedrig: niedrig,
                               sehrNiedrig: 0, extremNiedrig: 0, keineDaten: keine)
    }

    struct Station: Decodable { let timeseries: [Timeseries] }
    struct Timeseries: Decodable { let shortname: String; let currentMeasurement: Measurement? }
    struct Measurement: Decodable { let stateMnwMhw: String? }
}
