// Local swiftc test harness — mirrors the XCTest suite so TDD can run
// without SwiftPM (the CommandLineTools manifest link is broken in this env).
// Compile: swiftc Sources/TiefstandCore/*.swift Tests/manual/RunTests.swift -o testrunner
import Foundation

var failures = 0
func check(_ name: String, _ actual: Double, _ expected: Double, accuracy: Double = 0.1) {
    if abs(actual - expected) <= accuracy {
        print("  ✅ \(name)")
    } else {
        print("  ❌ \(name) — expected \(expected), got \(actual)")
        failures += 1
    }
}

print("DomainAggregate")
// Live-captured NIWIS discharge (ABFLUSS) aggregate, 2026-07-16.
// mean class index = (91·1 + 76·2 + 110·3) / 350 = 1.6371 → /3·100 = 54.57
let discharge = DomainAggregate(
    keinNiedrigwasser: 73, niedrig: 91, sehrNiedrig: 76, extremNiedrig: 110, keineDaten: 4)
check("severityScore maps four classes onto 0–100", discharge.severityScore ?? -1, 54.57)

print("DrynessIndex")
// Live-captured NIWIS groundwater (GRUNDWASSER) aggregate, 2026-07-16.
// score = (44 + 59·2 + 46·3) / 229 / 3 · 100 = 43.67
// combined = (54.57 + 43.67) / 2 = 49.12
let groundwater = DomainAggregate(
    keinNiedrigwasser: 80, niedrig: 44, sehrNiedrig: 59, extremNiedrig: 46, keineDaten: 3)
if let index = DrynessIndex.combined(discharge: discharge, groundwater: groundwater) {
    check("combined = 50/50 mean of discharge + groundwater", index.value, 49.12)
} else {
    print("  ❌ combined returned nil unexpectedly"); failures += 1
}

let empty = DomainAggregate(
    keinNiedrigwasser: 0, niedrig: 0, sehrNiedrig: 0, extremNiedrig: 0, keineDaten: 5)
if let index = DrynessIndex.combined(discharge: discharge, groundwater: empty) {
    check("combined ignores a domain without data", index.value, discharge.severityScore ?? -1, accuracy: 0.001)
} else {
    print("  ❌ combined returned nil with one populated domain"); failures += 1
}
if DrynessIndex.combined(discharge: empty, groundwater: empty) == nil {
    print("  ✅ combined is nil when no domain has data")
} else {
    print("  ❌ combined should be nil when no domain has data"); failures += 1
}

print(failures == 0 ? "\nALL GREEN" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
