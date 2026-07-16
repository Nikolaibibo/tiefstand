// make-icon.swift — render the Tiefstand app icon (water-in-a-squircle) to a
// 1024px PNG using AppKit. Run via `swift Scripts/make-icon.swift <out.png>`;
// Scripts/make-icon.sh turns it into a .icns. Kept as a script so the icon is
// reproducible from source and matches the app's hydro identity.
import AppKit

let size: CGFloat = 1024
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError("no context") }

let space = CGColorSpaceCreateDeviceRGB()
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a])!
}

let rect = CGRect(x: 0, y: 0, width: size, height: size)
let radius = size * 0.2237   // macOS squircle curvature
let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

// clip everything to the squircle
ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()

// deep-blue "vessel" background (y-up: top is darker)
let bg = CGGradient(colorsSpace: space,
                    colors: [rgb(0.04, 0.13, 0.19), rgb(0.07, 0.22, 0.30)] as CFArray,
                    locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])

// water surface parameters (y-up)
let fraction: CGFloat = 0.52
let level = size * fraction
let amp = size * 0.032
let steps = 96
func waveY(_ i: Int) -> CGFloat {
    level + sin(CGFloat(i) / CGFloat(steps) * .pi * 2.5) * amp
}

// water body: teal→blue fill from the wave surface down
var water = CGMutablePath()
water.move(to: CGPoint(x: 0, y: 0))
water.addLine(to: CGPoint(x: 0, y: waveY(0)))
for i in 0...steps { water.addLine(to: CGPoint(x: size * CGFloat(i) / CGFloat(steps), y: waveY(i))) }
water.addLine(to: CGPoint(x: size, y: 0))
water.closeSubpath()

ctx.saveGState()
ctx.addPath(water)
ctx.clip()
let fill = CGGradient(colorsSpace: space,
                      colors: [rgb(0.20, 0.68, 0.78), rgb(0.09, 0.40, 0.52)] as CFArray,
                      locations: [0, 1])!
ctx.drawLinearGradient(fill, start: CGPoint(x: 0, y: level), end: CGPoint(x: 0, y: 0), options: [])
ctx.restoreGState()

// white surface glint
var glint = CGMutablePath()
glint.move(to: CGPoint(x: 0, y: waveY(0)))
for i in 0...steps { glint.addLine(to: CGPoint(x: size * CGFloat(i) / CGFloat(steps), y: waveY(i))) }
ctx.addPath(glint)
ctx.setStrokeColor(rgb(1, 1, 1, 0.6))
ctx.setLineWidth(size * 0.012)
ctx.setLineCap(.round)
ctx.strokePath()

// soft top sheen for depth
let sheen = CGGradient(colorsSpace: space,
                       colors: [rgb(1, 1, 1, 0.10), rgb(1, 1, 1, 0)] as CFArray,
                       locations: [0, 1])!
ctx.drawLinearGradient(sheen, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: size * 0.7), options: [])

ctx.restoreGState()
image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { fatalError("encode failed") }
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
