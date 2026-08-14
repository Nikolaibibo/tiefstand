import SwiftUI
import AppKit
import TiefstandUI

// MARK: - Menu bar

struct MenuBarLabel: View {
    let index: Double?
    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: Self.glyphImage(for: index))
            Text(index.map { "\(Int($0.rounded()))" } ?? "–")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }

    /// The menu bar renders `Canvas`/`Shape` content in a `MenuBarExtra` label as
    /// blank, so we rasterize the glyph to a retina NSImage up front. `isTemplate
    /// = false` keeps the hydro colors instead of a monochrome mask.
    @MainActor
    static func glyphImage(for index: Double?) -> NSImage {
        let side: CGFloat = 15
        let renderer = ImageRenderer(content:
            MenuBarGlyph(index: index).frame(width: side, height: side))
        renderer.scale = 2
        guard let image = renderer.nsImage else {
            return NSImage(size: NSSize(width: side, height: side))
        }
        image.isTemplate = false
        return image
    }
}

/// A water-in-a-vessel disc tuned for the menu bar: a soft empty vessel, a vivid
/// wave-fill whose height tracks the index, a crisp rim, and a white surface
/// glint. Built from plain SwiftUI `Shape`s (not `Canvas`, which doesn't render
/// inside a `MenuBarExtra` label) and rasterized by `MenuBarLabel`, so it stays
/// legible and reads as a level — not a flat disc — at ~15pt over any wallpaper.
struct MenuBarGlyph: View {
    let index: Double?

    var body: some View {
        let tint = Hydro.rampColor(index ?? 0)
        let disc = Circle().inset(by: 1)
        ZStack {
            // soft empty vessel: the disc is always a filled shape, so the water
            // level reads against a container rather than the bare wallpaper.
            disc.fill(tint.opacity(0.16))

            if let index {
                let f = max(0.06, min(1, index / 100))
                WaveFillShape(fraction: f)
                    .fill(LinearGradient(
                        colors: [Hydro.rampColor(max(0, index - 18)), tint],
                        startPoint: .top, endPoint: .bottom))
                    .clipShape(disc)
                WaveSurfaceLine(fraction: f)
                    .stroke(.white.opacity(0.65), lineWidth: 0.8)
                    .clipShape(disc)
            }

            disc.stroke(tint.opacity(0.9), lineWidth: 1.2)
        }
    }
}

/// The sine surface line for a fill at `fraction` of the height.
private func waveSurface(in rect: CGRect, fraction: Double) -> (points: [CGPoint], level: CGFloat) {
    let level = rect.height * (1 - fraction)
    let amp = rect.height * 0.06
    let steps = 24
    let pts = (0...steps).map { i -> CGPoint in
        let x = rect.minX + rect.width * Double(i) / Double(steps)
        let y = level + sin(Double(i) / Double(steps) * .pi * 2) * amp
        return CGPoint(x: x, y: y)
    }
    return (pts, level)
}

/// Water filled from the bottom to `fraction` of the height, capped by a ripple.
struct WaveFillShape: Shape {
    var fraction: Double
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let (pts, _) = waveSurface(in: rect, fraction: fraction)
        p.addLines(pts)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Just the water surface line (for a glint highlight).
struct WaveSurfaceLine: Shape {
    var fraction: Double
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addLines(waveSurface(in: rect, fraction: fraction).points)
        return p
    }
}
