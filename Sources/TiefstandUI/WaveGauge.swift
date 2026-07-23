import SwiftUI

/// Circular gauge filled from the bottom with a gently moving sine surface.
/// The signature motif, shared by the popover and the widget. Pass
/// `animated: false` in contexts (like WidgetKit) that render a static snapshot.
public struct WaveGauge: View {
    var fraction: Double      // 0…1 fill height
    var index: Double         // drives color
    var animated: Bool

    public init(fraction: Double, index: Double, animated: Bool = true) {
        self.fraction = fraction
        self.index = index
        self.animated = animated
    }

    public var body: some View {
        if animated {
            TimelineView(.animation) { timeline in
                canvas(phase: timeline.date.timeIntervalSinceReferenceDate)
            }
        } else {
            canvas(phase: 0)
        }
    }

    private func canvas(phase: Double) -> some View {
        Canvas { ctx, size in
            let bounds = CGRect(origin: .zero, size: size)
            let ring = Path(ellipseIn: bounds.insetBy(dx: 0.5, dy: 0.5))

            // faint track
            ctx.stroke(ring, with: .color(Hydro.rampColor(index).opacity(0.25)),
                       lineWidth: max(1, size.width * 0.05))
            ctx.clip(to: ring)

            let f = max(0, min(1, fraction))
            let level = size.height * (1 - f)
            let amp = size.height * 0.05
            let wave = wavePath(in: size, level: level, amp: amp, phase: phase)

            ctx.fill(wave, with: .linearGradient(
                Gradient(colors: [Hydro.rampColor(max(0, index - 22)), Hydro.rampColor(index)]),
                startPoint: CGPoint(x: 0, y: level - amp),
                endPoint: CGPoint(x: 0, y: size.height)))

            // subtle surface highlight
            ctx.stroke(surfaceLine(in: size, level: level, amp: amp, phase: phase),
                       with: .color(.white.opacity(0.5)), lineWidth: 0.75)
        }
    }

    private func wavePath(in size: CGSize, level: CGFloat, amp: CGFloat, phase: Double) -> Path {
        var p = surfaceLine(in: size, level: level, amp: amp, phase: phase)
        p.addLine(to: CGPoint(x: size.width, y: size.height))
        p.addLine(to: CGPoint(x: 0, y: size.height))
        p.closeSubpath()
        return p
    }

    private func surfaceLine(in size: CGSize, level: CGFloat, amp: CGFloat, phase: Double) -> Path {
        var p = Path()
        let steps = 28
        for i in 0...steps {
            let x = size.width * Double(i) / Double(steps)
            let y = level + sin(Double(i) / Double(steps) * .pi * 2 + phase * 1.6) * amp
            if i == 0 { p.move(to: CGPoint(x: x, y: y)) }
            else { p.addLine(to: CGPoint(x: x, y: y)) }
        }
        return p
    }
}
