import SwiftUI
import TiefstandCore

/// Hydro identity: a blue→red severity ramp. Wet/calm reads teal-blue,
/// extreme drought reads deep red. Shared by the app and the widget so both
/// speak the same visual language.
public enum Hydro {
    /// Continuous ramp for an index value 0…100.
    public static func rampColor(_ index: Double) -> Color {
        let t = max(0, min(1, index / 100))
        // teal → amber → red, interpolated in two legs.
        let cool = RGB(0.16, 0.62, 0.71)   // #29A0B5
        let mid  = RGB(0.95, 0.71, 0.22)   // #F2B538
        let hot  = RGB(0.83, 0.24, 0.24)   // #D43D3D
        let rgb = t < 0.5 ? cool.lerp(to: mid, t: t / 0.5)
                          : mid.lerp(to: hot, t: (t - 0.5) / 0.5)
        return rgb.color
    }

    /// A two-stop gradient around an index value, for gauge fills.
    public static func gradient(_ index: Double) -> LinearGradient {
        let base = rampColor(index)
        let light = rampColor(max(0, index - 22))
        return LinearGradient(colors: [light, base],
                              startPoint: .top, endPoint: .bottom)
    }

    /// Discrete color per low-water class (for donut segments).
    public static func classColor(_ c: LowWaterClass) -> Color {
        switch c {
        case .none:         return RGB(0.16, 0.62, 0.71).color
        case .low:          return RGB(0.95, 0.71, 0.22).color
        case .veryLow:      return RGB(0.90, 0.49, 0.20).color
        case .extremelyLow: return RGB(0.83, 0.24, 0.24).color
        }
    }
}

extension DrynessLevel {
    public var color: Color {
        switch self {
        case .normal:   return Hydro.rampColor(12)
        case .elevated: return Hydro.rampColor(37)
        case .high:     return Hydro.rampColor(62)
        case .severe:   return Hydro.rampColor(88)
        }
    }
}

extension Trend {
    public var symbolName: String {
        switch self {
        case .rising:  return "arrow.up.right"
        case .falling: return "arrow.down.right"
        case .steady:  return "arrow.right"
        }
    }
}

/// Tiny RGB helper for interpolation (avoids UIKit/AppKit color math).
struct RGB {
    let r, g, b: Double
    init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
    func lerp(to other: RGB, t: Double) -> RGB {
        RGB(r + (other.r - r) * t, g + (other.g - g) * t, b + (other.b - b) * t)
    }
    var color: Color { Color(red: r, green: g, blue: b) }
}
