import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fatalError("Usage: generate-app-icon.swift output.png")
}

let size = 1024
let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
)!
let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = graphics
graphics.imageInterpolation = .high

let bounds = CGRect(x: 0, y: 0, width: size, height: size)
let background = NSBezierPath(roundedRect: bounds.insetBy(dx: 18, dy: 18), xRadius: 225, yRadius: 225)
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.12, green: 0.18, blue: 0.25, alpha: 1),
    NSColor(calibratedRed: 0.035, green: 0.055, blue: 0.082, alpha: 1)
])!
gradient.draw(in: background, angle: -45)

let inset = NSBezierPath(roundedRect: bounds.insetBy(dx: 72, dy: 72), xRadius: 185, yRadius: 185)
NSColor(calibratedWhite: 1, alpha: 0.035).setFill()
inset.fill()
NSColor(calibratedWhite: 1, alpha: 0.11).setStroke()
inset.lineWidth = 5
inset.stroke()

func arrow(_ points: [CGPoint], color: NSColor, head: CGPoint, left: CGPoint, right: CGPoint) {
    let path = NSBezierPath()
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.lineWidth = 50
    path.move(to: points[0])
    for point in points.dropFirst() { path.line(to: point) }
    color.setStroke()
    path.stroke()
    let tip = NSBezierPath()
    tip.lineCapStyle = .round
    tip.lineJoinStyle = .round
    tip.lineWidth = 50
    tip.move(to: left)
    tip.line(to: head)
    tip.line(to: right)
    tip.stroke()
}

arrow(
    [CGPoint(x: 275, y: 650), CGPoint(x: 365, y: 740), CGPoint(x: 610, y: 740), CGPoint(x: 690, y: 660)],
    color: NSColor(calibratedRed: 0.74, green: 0.94, blue: 0.48, alpha: 1),
    head: CGPoint(x: 690, y: 660), left: CGPoint(x: 610, y: 665), right: CGPoint(x: 685, y: 740)
)
arrow(
    [CGPoint(x: 750, y: 375), CGPoint(x: 660, y: 285), CGPoint(x: 415, y: 285), CGPoint(x: 335, y: 365)],
    color: NSColor(calibratedRed: 0.34, green: 0.82, blue: 0.88, alpha: 1),
    head: CGPoint(x: 335, y: 365), left: CGPoint(x: 415, y: 360), right: CGPoint(x: 340, y: 285)
)

let center = NSBezierPath(ovalIn: CGRect(x: 442, y: 442, width: 140, height: 140))
NSColor(calibratedRed: 0.96, green: 0.98, blue: 0.94, alpha: 1).setFill()
center.fill()
let core = NSBezierPath(ovalIn: CGRect(x: 483, y: 483, width: 58, height: 58))
NSColor(calibratedRed: 0.13, green: 0.19, blue: 0.24, alpha: 1).setFill()
core.fill()

NSGraphicsContext.restoreGraphicsState()
let png = bitmap.representation(using: .png, properties: [:])!
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
