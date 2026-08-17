import AppKit

let dim: CGFloat = 512

guard let rep = NSBitmapImageRep(
  bitmapDataPlanes: nil,
  pixelsWide: Int(dim),
  pixelsHigh: Int(dim),
  bitsPerSample: 8,
  samplesPerPixel: 4,
  hasAlpha: true,
  isPlanar: false,
  colorSpaceName: .deviceRGB,
  bytesPerRow: 0,
  bitsPerPixel: 0
) else {
  fatalError("bitmap")
}
rep.size = NSSize(width: dim, height: dim)

NSGraphicsContext.saveGraphicsState()
guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { fatalError("ctx") }
NSGraphicsContext.current = ctx
ctx.shouldAntialias = true
ctx.imageInterpolation = .high
let cg = ctx.cgContext
cg.setShouldAntialias(true)

func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
  NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}

let bg = srgb(0.086, 0.086, 0.090)
let card = srgb(0.172, 0.172, 0.180)
let ink = srgb(0.93, 0.94, 0.95)
let accent = srgb(1.00, 0.23, 0.19)

bg.setFill()
NSRect(x: 0, y: 0, width: dim, height: dim).fill()

let inset: CGFloat = 88
let frame = NSRect(x: inset, y: inset, width: dim - inset * 2, height: dim - inset * 2)
let radius: CGFloat = 44
let cardPath = NSBezierPath(roundedRect: frame, xRadius: radius, yRadius: radius)
card.setFill()
cardPath.fill()

func cropMark(origin: NSPoint, xSign: CGFloat, ySign: CGFloat) {
  let arm: CGFloat = 62
  let path = NSBezierPath()
  path.lineCapStyle = .round
  path.lineJoinStyle = .round
  path.lineWidth = 22
  path.move(to: NSPoint(x: origin.x + xSign * arm, y: origin.y))
  path.line(to: origin)
  path.line(to: NSPoint(x: origin.x, y: origin.y + ySign * arm))
  ink.setStroke()
  path.stroke()
}

let pad: CGFloat = 28
cropMark(origin: NSPoint(x: frame.minX + pad, y: frame.maxY - pad), xSign: 1, ySign: -1)
cropMark(origin: NSPoint(x: frame.maxX - pad, y: frame.maxY - pad), xSign: -1, ySign: -1)
cropMark(origin: NSPoint(x: frame.minX + pad, y: frame.minY + pad), xSign: 1, ySign: 1)
cropMark(origin: NSPoint(x: frame.maxX - pad, y: frame.minY + pad), xSign: -1, ySign: 1)

let start = NSPoint(x: 176, y: 176)
let end = NSPoint(x: 348, y: 344)
let angle = atan2(end.y - start.y, end.x - start.x)
let head: CGFloat = 50
let shaftEnd = NSPoint(
  x: end.x - cos(angle) * 30,
  y: end.y - sin(angle) * 30
)

let shaft = NSBezierPath()
shaft.lineWidth = 24
shaft.lineCapStyle = .round
shaft.move(to: start)
shaft.line(to: shaftEnd)
accent.setStroke()
shaft.stroke()

let spread: CGFloat = 22
let left = NSPoint(
  x: end.x - cos(angle) * head + cos(angle + .pi / 2) * spread,
  y: end.y - sin(angle) * head + sin(angle + .pi / 2) * spread
)
let right = NSPoint(
  x: end.x - cos(angle) * head + cos(angle - .pi / 2) * spread,
  y: end.y - sin(angle) * head + sin(angle - .pi / 2) * spread
)
let headPath = NSBezierPath()
headPath.move(to: end)
headPath.line(to: left)
headPath.line(to: right)
headPath.close()
accent.setFill()
headPath.fill()

NSGraphicsContext.restoreGraphicsState()

guard let data = rep.representation(using: .png, properties: [:]) else { fatalError("png") }
let url = URL(fileURLWithPath: CommandLine.arguments[1])
try data.write(to: url)
print("Wrote \(url.path)")
