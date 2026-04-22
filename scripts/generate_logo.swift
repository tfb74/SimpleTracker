import AppKit
import CoreGraphics

// Renders the SimpleTracking app icon at 1024x1024.
// Composition (CG y grows UP):
//   • dark anthracite background
//   • dotted curve = "planned route" from bottom-left to top-right
//   • solid main chart line from pin -> data points -> checkmark circle
//   • teardrop location pin at bottom-left
//   • checkmark circle at top-right
// Usage: swift generate_logo.swift <output.png>

guard CommandLine.arguments.count >= 2 else {
    print("usage: generate_logo.swift <output.png>"); exit(1)
}
let outPath = CommandLine.arguments[1]

let W = 1024, H = 1024
let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil, width: W, height: H,
    bitsPerComponent: 8, bytesPerRow: 0,
    space: cs,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { exit(1) }

// --- 1. Background gradient ---------------------------------------------
let bg = [
    CGColor(red: 0.17, green: 0.18, blue: 0.20, alpha: 1),
    CGColor(red: 0.08, green: 0.09, blue: 0.10, alpha: 1)
] as CFArray
let bgGrad = CGGradient(colorsSpace: cs, colors: bg, locations: [0, 1])!
ctx.drawLinearGradient(bgGrad,
    start: CGPoint(x: 0, y: CGFloat(H)),
    end:   CGPoint(x: CGFloat(W), y: 0),
    options: [])

// --- Reusable colors -----------------------------------------------------
let accent    = CGColor(red: 0.85, green: 0.91, blue: 0.99, alpha: 1)  // icy white-blue
let accentDim = CGColor(red: 0.55, green: 0.62, blue: 0.75, alpha: 1)
let dark      = CGColor(red: 0.10, green: 0.11, blue: 0.13, alpha: 1)

// --- Chart waypoints (line chart) ---------------------------------------
let p1 = CGPoint(x: 300, y: 380)    // start (near the pin)
let p2 = CGPoint(x: 470, y: 520)
let p3 = CGPoint(x: 640, y: 620)
let p4 = CGPoint(x: 820, y: 770)    // end (checkmark anchor)

// --- 2. Dotted planned route --------------------------------------------
ctx.saveGState()
ctx.setStrokeColor(accentDim)
ctx.setLineWidth(16)
ctx.setLineCap(.round)
ctx.setLineDash(phase: 0, lengths: [0.1, 46])
let dotted = CGMutablePath()
dotted.move(to: CGPoint(x: 220, y: 260))
dotted.addCurve(
    to: CGPoint(x: 880, y: 640),
    control1: CGPoint(x: 320, y: 180),
    control2: CGPoint(x: 720, y: 320)
)
ctx.addPath(dotted)
ctx.strokePath()
ctx.restoreGState()

// --- 3. Main chart line -------------------------------------------------
ctx.setStrokeColor(accent)
ctx.setLineWidth(34)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
let line = CGMutablePath()
line.move(to: p1)
line.addCurve(to: p2,
    control1: CGPoint(x: 360, y: 400),
    control2: CGPoint(x: 400, y: 490))
line.addCurve(to: p3,
    control1: CGPoint(x: 540, y: 550),
    control2: CGPoint(x: 570, y: 590))
line.addCurve(to: p4,
    control1: CGPoint(x: 720, y: 660),
    control2: CGPoint(x: 760, y: 720))
ctx.addPath(line)
ctx.strokePath()

// --- 4. Data points -----------------------------------------------------
func drawDataPoint(at p: CGPoint, radius: CGFloat) {
    ctx.setFillColor(dark)
    ctx.fillEllipse(in: CGRect(x: p.x - radius, y: p.y - radius,
                               width: radius*2, height: radius*2))
    let r = radius - 14
    ctx.setFillColor(accent)
    ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r*2, height: r*2))
}
drawDataPoint(at: p2, radius: 46)
drawDataPoint(at: p3, radius: 46)

// --- 5. Location pin (teardrop) -----------------------------------------
// The pin: a circle joined with two tangent lines meeting at a tip below.
let pinCx: CGFloat = 245
let pinCy: CGFloat = 310            // center of the round head
let pinR:  CGFloat = 110            // head radius
let pinTipY: CGFloat = 130          // tip y (below the head)

// Tangent angles from tip to circle: sinθ = r / d ; d = distance(tip -> center).
let dx = CGFloat(0)
let dy = pinCy - pinTipY
let d  = hypot(dx, dy)
let theta = asin(pinR / d)          // half-angle at the tip
// Two tangent points on the circle:
let tpLeft  = CGPoint(
    x: pinCx + pinR * sin(-theta - .pi/2 + .pi),
    y: pinCy + pinR * -cos(-theta - .pi/2 + .pi)
)
// Simpler: compute tangent points from tip angle.
// Easier geometry: the pin is symmetric about the vertical axis x = pinCx.
let alpha = asin(pinR / d)          // angle between tip->center and tip->tangent
// tangent on the left side of the pin
let tipToCenterAngle = atan2(pinCy - pinTipY, 0)  // = π/2 (straight up)
let leftAngle  = tipToCenterAngle + alpha
let rightAngle = tipToCenterAngle - alpha
// tangent points: on the circle, at angle perpendicular to the tangent line.
// For a circle tangent from an external point, the tangent point lies at
// angle (tipAngle ± (π/2 - alpha)) measured at the center.
let tpAngleLeft  = leftAngle  - .pi/2 + .pi   // ugh
let tpAngleRight = rightAngle + .pi/2 + .pi
// Actually: easier to just draw the pin path with a single arc + line:
// 1) start at the tip,
// 2) arc from tip-to-left-tangent-point along the circle back to right-tangent-point,
// 3) line back to tip.
// Using addArc(tangent1End:tangent2End:radius:) fits exactly.
let tip = CGPoint(x: pinCx, y: pinTipY)
let topLeft  = CGPoint(x: pinCx - pinR * 1.5, y: pinCy + pinR * 1.2)
let topRight = CGPoint(x: pinCx + pinR * 1.5, y: pinCy + pinR * 1.2)

let pin = CGMutablePath()
pin.move(to: tip)
pin.addArc(tangent1End: topLeft,  tangent2End: topRight, radius: pinR)
pin.addArc(tangent1End: topRight, tangent2End: tip,       radius: pinR)
pin.addLine(to: tip)
pin.closeSubpath()

// Gradient-filled pin body.
ctx.saveGState()
ctx.addPath(pin)
ctx.clip()
let pinColors = [
    CGColor(red: 0.94, green: 0.96, blue: 1.00, alpha: 1),
    CGColor(red: 0.60, green: 0.68, blue: 0.82, alpha: 1)
] as CFArray
let pinGrad = CGGradient(colorsSpace: cs, colors: pinColors, locations: [0, 1])!
ctx.drawLinearGradient(pinGrad,
    start: CGPoint(x: 0, y: pinCy + pinR),
    end:   CGPoint(x: 0, y: pinTipY - 20),
    options: [])
ctx.restoreGState()

// Pin hole.
ctx.setFillColor(dark)
ctx.fillEllipse(in: CGRect(
    x: pinCx - 38, y: pinCy - 38,
    width: 76, height: 76
))

// --- 6. Checkmark circle at end of line ---------------------------------
let checkCenter = p4
let checkRadius: CGFloat = 92

ctx.setFillColor(accent)
ctx.fillEllipse(in: CGRect(
    x: checkCenter.x - checkRadius, y: checkCenter.y - checkRadius,
    width: checkRadius*2, height: checkRadius*2
))
ctx.setStrokeColor(dark)
ctx.setLineWidth(26)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.move(to: CGPoint(x: checkCenter.x - 42, y: checkCenter.y + 4))
ctx.addLine(to: CGPoint(x: checkCenter.x - 8,  y: checkCenter.y - 30))
ctx.addLine(to: CGPoint(x: checkCenter.x + 44, y: checkCenter.y + 36))
ctx.strokePath()

// --- Export --------------------------------------------------------------
guard let image = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: image)
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! data.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
