import Foundation

/// A qualitative band for a `DrynessIndex` value, used to drive the
/// menu-bar color and label. Splits 0–100 at the quarters.
public enum DrynessLevel: String, CaseIterable, Equatable {
    case normal
    case elevated
    case high
    case severe

    public init(index: Double) {
        switch index {
        case ..<25: self = .normal
        case ..<50: self = .elevated
        case ..<75: self = .high
        default:    self = .severe
        }
    }

    public var label: String {
        switch self {
        case .normal:   return "Normal"
        case .elevated: return "Elevated"
        case .high:     return "High"
        case .severe:   return "Severe"
        }
    }
}
