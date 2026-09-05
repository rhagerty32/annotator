import AppKit
import CoreGraphics
import Foundation
import SwiftUI

enum Tool: String, CaseIterable, Identifiable {
  case select
  case rectangle
  case circle
  case arrow
  case line
  case draw
  case cross
  case text
  case highlight
  case spotlight
  case numbered
  case redact
  case crop

  var id: String { rawValue }

  var hotkey: String {
    switch self {
    case .select: return "v"
    case .rectangle: return "r"
    case .circle: return "c"
    case .arrow: return "a"
    case .line: return "l"
    case .draw: return "d"
    case .cross: return "x"
    case .text: return "t"
    case .highlight: return "h"
    case .spotlight: return "i"
    case .numbered: return "n"
    case .redact: return "b"
    case .crop: return "k"
    }
  }

  var label: String {
    switch self {
    case .select: return "Select"
    case .rectangle: return "Rectangle"
    case .circle: return "Circle"
    case .arrow: return "Arrow"
    case .line: return "Line"
    case .draw: return "Draw"
    case .cross: return "Cross"
    case .text: return "Text"
    case .highlight: return "Fill"
    case .spotlight: return "Spotlight"
    case .numbered: return "Steps"
    case .redact: return "Redact"
    case .crop: return "Crop"
    }
  }

  var symbolName: String {
    switch self {
    case .select: return "cursorarrow"
    case .rectangle: return "rectangle"
    case .circle: return "circle"
    case .arrow: return "arrow.up.right"
    case .line: return "line.diagonal"
    case .draw: return "scribble.variable"
    case .cross: return "xmark"
    case .text: return "textformat"
    case .highlight: return "paintbrush.pointed.fill"
    case .spotlight: return "viewfinder"
    case .numbered: return "list.number"
    case .redact: return "eye.slash"
    case .crop: return "crop"
    }
  }

  var placesOnClick: Bool {
    self == .text || self == .numbered
  }

  var drawsLine: Bool {
    self == .arrow || self == .line
  }

  var drawsShape: Bool {
    switch self {
    case .rectangle, .circle, .arrow, .line, .cross, .highlight, .spotlight, .redact, .crop:
      return true
    default:
      return false
    }
  }

  init?(hotkey: Character) {
    let key = String(hotkey).lowercased()
    guard let match = Self.allCases.first(where: { $0.hotkey == key }) else { return nil }
    self = match
  }
}

struct ToolPaletteGroup: Identifiable {
  let id: String
  let title: String
  let tools: [Tool]

  static let toolbar: [ToolPaletteGroup] = [
    ToolPaletteGroup(id: "shapes", title: "Shapes", tools: [
      .rectangle, .circle, .arrow, .line, .draw, .cross,
    ]),
    ToolPaletteGroup(id: "callouts", title: "Callouts", tools: [
      .text, .highlight, .spotlight, .numbered,
    ]),
    ToolPaletteGroup(id: "cut", title: "Cut", tools: [
      .redact, .crop,
    ]),
  ]

  static let overlay: [ToolPaletteGroup] = [
    ToolPaletteGroup(id: "select", title: "Select", tools: [.select]),
  ] + toolbar
}

enum AnnotationColor: String, CaseIterable, Identifiable, Equatable {
  case red
  case orange
  case yellow
  case green
  case mint
  case cyan
  case blue
  case purple
  case pink
  case white

  var id: String { rawValue }

  /// Keyboard digit 1…9, 0 for white.
  var digitHotkey: String {
    switch self {
    case .red: return "1"
    case .orange: return "2"
    case .yellow: return "3"
    case .green: return "4"
    case .mint: return "5"
    case .cyan: return "6"
    case .blue: return "7"
    case .purple: return "8"
    case .pink: return "9"
    case .white: return "0"
    }
  }

  var swatch: Color {
    switch self {
    case .red: return Color(red: 1.00, green: 0.23, blue: 0.19)
    case .orange: return Color(red: 1.00, green: 0.58, blue: 0.00)
    case .yellow: return Color(red: 1.00, green: 0.890, blue: 0.455)
    case .green: return Color(red: 0.20, green: 0.78, blue: 0.35)
    case .mint: return Color(red: 0.00, green: 0.78, blue: 0.75)
    case .cyan: return Color(red: 0.20, green: 0.78, blue: 0.94)
    case .blue: return Color(red: 0.20, green: 0.48, blue: 1.00)
    case .purple: return Color(red: 0.69, green: 0.32, blue: 0.87)
    case .pink: return Color(red: 1.00, green: 0.33, blue: 0.64)
    case .white: return Color(red: 0.98, green: 0.98, blue: 0.98)
    }
  }
}

enum ResizeHandle: Equatable {
  case topLeft, topRight, bottomLeft, bottomRight
  case rectRadius
  case arrowStart, arrowEnd, arrowCurve
}

struct Annotation: Identifiable, Equatable {
  let id: UUID
  var kind: Kind
  var color: AnnotationColor
  var strokeWidth: CGFloat

  enum Kind: Equatable {
    case rectangle(CGRect, radius: CGFloat)
    case circle(CGRect)
    case cross(CGRect)
    case highlight(CGRect)
    case spotlight(CGRect)
    case redact(CGRect)
    case arrow(start: CGPoint, end: CGPoint, control: CGPoint?, headed: Bool)
    case path([CGPoint])
    case text(origin: CGPoint, string: String)
    case badge(origin: CGPoint, index: Int)
  }

  init(
    id: UUID = UUID(),
    kind: Kind,
    color: AnnotationColor = .red,
    strokeWidth: CGFloat = 3
  ) {
    self.id = id
    self.kind = kind
    self.color = color
    self.strokeWidth = strokeWidth
  }

  func copying(
    kind: Kind? = nil,
    color: AnnotationColor? = nil,
    strokeWidth: CGFloat? = nil
  ) -> Annotation {
    Annotation(
      id: id,
      kind: kind ?? self.kind,
      color: color ?? self.color,
      strokeWidth: strokeWidth ?? self.strokeWidth
    )
  }

  var boundingRect: CGRect {
    switch kind {
    case let .rectangle(rect, _), let .circle(rect), let .cross(rect), let .highlight(rect),
         let .spotlight(rect), let .redact(rect):
      return rect.normalized
    case let .arrow(start, end, control, _):
      let c = control ?? midpoint(start, end)
      let minX = min(start.x, end.x, c.x)
      let minY = min(start.y, end.y, c.y)
      let maxX = max(start.x, end.x, c.x)
      let maxY = max(start.y, end.y, c.y)
      return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        .insetBy(dx: -8, dy: -8)
    case let .path(points):
      guard let first = points.first else { return .zero }
      var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
      for p in points.dropFirst() {
        minX = min(minX, p.x); maxX = max(maxX, p.x)
        minY = min(minY, p.y); maxY = max(maxY, p.y)
      }
      return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        .insetBy(dx: -6, dy: -6)
    case let .text(origin, string):
      let width = max(40, CGFloat(string.count) * 9)
      let height: CGFloat = 22
      return CGRect(x: origin.x, y: origin.y, width: width, height: height)
    case let .badge(origin, _):
      return CGRect(x: origin.x - 16, y: origin.y - 16, width: 32, height: 32)
    }
  }

  func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool {
    switch kind {
    case let .rectangle(rect, _):
      let r = rect.normalized.insetBy(dx: -tolerance, dy: -tolerance)
      let inner = rect.normalized.insetBy(dx: tolerance, dy: tolerance)
      return r.contains(point) && (inner.width <= 0 || inner.height <= 0 || !inner.contains(point))
    case let .circle(rect):
      let r = rect.normalized
      let center = CGPoint(x: r.midX, y: r.midY)
      let rx = r.width / 2
      let ry = r.height / 2
      guard rx > 0, ry > 0 else { return false }
      let dx = (point.x - center.x) / rx
      let dy = (point.y - center.y) / ry
      let d = dx * dx + dy * dy
      let outer = 1 + tolerance / max(rx, ry)
      let inner = max(0, 1 - tolerance / max(rx, ry))
      return d <= outer * outer && d >= inner * inner
    case let .cross(rect):
      let r = rect.normalized
      let a = CGPoint(x: r.minX, y: r.minY)
      let b = CGPoint(x: r.maxX, y: r.maxY)
      let c = CGPoint(x: r.maxX, y: r.minY)
      let d = CGPoint(x: r.minX, y: r.maxY)
      return min(distanceToSegment(point, a, b), distanceToSegment(point, c, d)) <= tolerance + 2
    case let .highlight(rect), let .spotlight(rect), let .redact(rect):
      return rect.normalized.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
    case let .arrow(start, end, control, _):
      if let control {
        return distanceToQuadratic(point, start: start, control: control, end: end) <= tolerance + 2
      }
      return distanceToSegment(point, start, end) <= tolerance + 2
    case let .path(points):
      guard points.count >= 2 else {
        return points.first.map { hypot(point.x - $0.x, point.y - $0.y) <= tolerance } ?? false
      }
      for i in 0..<(points.count - 1) {
        if distanceToSegment(point, points[i], points[i + 1]) <= tolerance + 2 {
          return true
        }
      }
      return false
    case .text:
      return boundingRect.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
    case let .badge(origin, _):
      return hypot(point.x - origin.x, point.y - origin.y) <= 16 + tolerance
    }
  }

  func translated(by delta: CGPoint) -> Annotation {
    switch kind {
    case let .rectangle(rect, radius):
      return copying(kind: .rectangle(rect.offsetBy(dx: delta.x, dy: delta.y), radius: radius))
    case let .circle(rect):
      return copying(kind: .circle(rect.offsetBy(dx: delta.x, dy: delta.y)))
    case let .cross(rect):
      return copying(kind: .cross(rect.offsetBy(dx: delta.x, dy: delta.y)))
    case let .highlight(rect):
      return copying(kind: .highlight(rect.offsetBy(dx: delta.x, dy: delta.y)))
    case let .spotlight(rect):
      return copying(kind: .spotlight(rect.offsetBy(dx: delta.x, dy: delta.y)))
    case let .redact(rect):
      return copying(kind: .redact(rect.offsetBy(dx: delta.x, dy: delta.y)))
    case let .arrow(start, end, control, headed):
      return copying(kind: .arrow(
        start: CGPoint(x: start.x + delta.x, y: start.y + delta.y),
        end: CGPoint(x: end.x + delta.x, y: end.y + delta.y),
        control: control.map { CGPoint(x: $0.x + delta.x, y: $0.y + delta.y) },
        headed: headed
      ))
    case let .path(points):
      return copying(kind: .path(points.map { CGPoint(x: $0.x + delta.x, y: $0.y + delta.y) }))
    case let .text(origin, string):
      return copying(kind: .text(
        origin: CGPoint(x: origin.x + delta.x, y: origin.y + delta.y),
        string: string
      ))
    case let .badge(origin, index):
      return copying(kind: .badge(
        origin: CGPoint(x: origin.x + delta.x, y: origin.y + delta.y),
        index: index
      ))
    }
  }

  func resized(handle: ResizeHandle, to point: CGPoint) -> Annotation {
    switch kind {
    case let .rectangle(rect, radius):
      if handle == .rectRadius {
        let r = rect.normalized
        var next = max(0, point.x - r.minX)
        next = min(next, min(r.width, r.height) / 2)
        if next < 8 { next = 0 }
        return copying(kind: .rectangle(r, radius: next))
      }
      let resized = resize(rect.normalized, handle: handle, to: point)
      let clamped = min(radius, min(resized.width, resized.height) / 2)
      return copying(kind: .rectangle(resized, radius: clamped))
    case let .circle(rect):
      return copying(kind: .circle(resize(rect.normalized, handle: handle, to: point)))
    case let .cross(rect):
      return copying(kind: .cross(resize(rect.normalized, handle: handle, to: point)))
    case let .highlight(rect):
      return copying(kind: .highlight(resize(rect.normalized, handle: handle, to: point)))
    case let .spotlight(rect):
      return copying(kind: .spotlight(resize(rect.normalized, handle: handle, to: point)))
    case let .redact(rect):
      return copying(kind: .redact(resize(rect.normalized, handle: handle, to: point)))
    case let .arrow(start, end, control, headed):
      switch handle {
      case .arrowStart:
        return copying(kind: .arrow(start: point, end: end, control: control, headed: headed))
      case .arrowEnd:
        return copying(kind: .arrow(start: start, end: point, control: control, headed: headed))
      case .arrowCurve:
        let next = arrowControl(fromApex: point, start: start, end: end)
        let slack = max(12, hypot(end.x - start.x, end.y - start.y) * 0.03)
        let snapped = distanceToSegment(point, start, end) < slack ? nil : next
        return copying(kind: .arrow(start: start, end: end, control: snapped, headed: headed))
      default:
        return self
      }
    default:
      return self
    }
  }

  var resizeHandles: [ResizeHandle] {
    switch kind {
    case .rectangle:
      return [.topLeft, .topRight, .bottomLeft, .bottomRight, .rectRadius]
    case .circle, .cross, .highlight, .spotlight, .redact:
      return [.topLeft, .topRight, .bottomLeft, .bottomRight]
    case .arrow:
      return [.arrowStart, .arrowEnd, .arrowCurve]
    default:
      return []
    }
  }

  func handlePoint(_ handle: ResizeHandle) -> CGPoint? {
    switch kind {
    case let .rectangle(rect, radius):
      let r = rect.normalized
      switch handle {
      case .topLeft: return CGPoint(x: r.minX, y: r.minY)
      case .topRight: return CGPoint(x: r.maxX, y: r.minY)
      case .bottomLeft: return CGPoint(x: r.minX, y: r.maxY)
      case .bottomRight: return CGPoint(x: r.maxX, y: r.maxY)
      case .rectRadius:
        let inset = min(max(18, radius), max(18, r.width * 0.35))
        return CGPoint(x: r.minX + inset, y: r.minY)
      default: return nil
      }
    case let .circle(rect), let .cross(rect), let .highlight(rect), let .spotlight(rect),
         let .redact(rect):
      let r = rect.normalized
      switch handle {
      case .topLeft: return CGPoint(x: r.minX, y: r.minY)
      case .topRight: return CGPoint(x: r.maxX, y: r.minY)
      case .bottomLeft: return CGPoint(x: r.minX, y: r.maxY)
      case .bottomRight: return CGPoint(x: r.maxX, y: r.maxY)
      default: return nil
      }
    case let .arrow(start, end, control, _):
      switch handle {
      case .arrowStart: return start
      case .arrowEnd: return end
      case .arrowCurve: return arrowApex(start: start, end: end, control: control)
      default: return nil
      }
    default:
      return nil
    }
  }
}

enum Draft: Equatable {
  case shape(start: CGPoint, current: CGPoint)
  case path([CGPoint])
  case textPlacement(CGPoint)
}

enum DragSession: Equatable {
  case draw
  case move(id: UUID, startPoint: CGPoint, original: Annotation, duplicated: Bool)
  case resize(id: UUID, handle: ResizeHandle, original: Annotation)
}

struct PointerMods: Equatable {
  var shift = false
  var option = false

  static var current: PointerMods {
    let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
    return PointerMods(shift: flags.contains(.shift), option: flags.contains(.option))
  }
}

extension CGRect {
  var normalized: CGRect {
    CGRect(
      x: min(origin.x, origin.x + size.width),
      y: min(origin.y, origin.y + size.height),
      width: abs(size.width),
      height: abs(size.height)
    )
  }
}

func shapeRect(from start: CGPoint, to current: CGPoint, mods: PointerMods) -> CGRect {
  var end = current
  if mods.shift {
    let dx = current.x - start.x
    let dy = current.y - start.y
    let side = max(abs(dx), abs(dy))
    end = CGPoint(
      x: start.x + side * (dx < 0 ? -1 : 1),
      y: start.y + side * (dy < 0 ? -1 : 1)
    )
  }

  if mods.option {
    let dx = end.x - start.x
    let dy = end.y - start.y
    return CGRect(
      x: start.x - dx,
      y: start.y - dy,
      width: dx * 2,
      height: dy * 2
    ).normalized
  }

  return CGRect(
    x: start.x,
    y: start.y,
    width: end.x - start.x,
    height: end.y - start.y
  ).normalized
}

func snapArrow(from start: CGPoint, to current: CGPoint, constrain: Bool) -> (CGPoint, CGPoint) {
  guard constrain else { return (start, current) }
  let dx = current.x - start.x
  let dy = current.y - start.y
  let dist = hypot(dx, dy)
  guard dist > 0.001 else { return (start, current) }
  let angle = atan2(dy, dx)
  let snapped = (angle / (.pi / 4)).rounded() * (.pi / 4)
  let end = CGPoint(x: start.x + dist * cos(snapped), y: start.y + dist * sin(snapped))
  return (start, end)
}

func crossPath(_ rect: CGRect) -> Path {
  let r = rect.normalized
  var path = Path()
  path.move(to: CGPoint(x: r.minX, y: r.minY))
  path.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
  path.move(to: CGPoint(x: r.maxX, y: r.minY))
  path.addLine(to: CGPoint(x: r.minX, y: r.maxY))
  return path
}

func roundedRectPath(_ rect: CGRect, radius: CGFloat) -> Path {
  let r = rect.normalized
  let rad = min(max(0, radius), min(r.width, r.height) / 2)
  if rad < 0.5 { return Path(r) }
  return Path(roundedRect: r, cornerRadius: rad, style: .continuous)
}

func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
  CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
}

func quadraticPoint(start: CGPoint, control: CGPoint, end: CGPoint, t: CGFloat) -> CGPoint {
  let u = 1 - t
  return CGPoint(
    x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
    y: u * u * start.y + 2 * u * t * control.y + t * t * end.y
  )
}

func arrowApex(start: CGPoint, end: CGPoint, control: CGPoint?) -> CGPoint {
  quadraticPoint(start: start, control: control ?? midpoint(start, end), end: end, t: 0.5)
}

func arrowControl(fromApex apex: CGPoint, start: CGPoint, end: CGPoint) -> CGPoint {
  CGPoint(
    x: 2 * apex.x - (start.x + end.x) / 2,
    y: 2 * apex.y - (start.y + end.y) / 2
  )
}

func distanceToQuadratic(
  _ p: CGPoint,
  start: CGPoint,
  control: CGPoint,
  end: CGPoint
) -> CGFloat {
  var best = CGFloat.greatestFiniteMagnitude
  var prev = start
  let steps = 24
  for i in 1...steps {
    let t = CGFloat(i) / CGFloat(steps)
    let cur = quadraticPoint(start: start, control: control, end: end, t: t)
    best = min(best, distanceToSegment(p, prev, cur))
    prev = cur
  }
  return best
}

private func distanceToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
  let dx = b.x - a.x
  let dy = b.y - a.y
  let len2 = dx * dx + dy * dy
  if len2 < 0.0001 {
    return hypot(p.x - a.x, p.y - a.y)
  }
  let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
  let proj = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
  return hypot(p.x - proj.x, p.y - proj.y)
}

private func resize(_ rect: CGRect, handle: ResizeHandle, to point: CGPoint) -> CGRect {
  var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
  var p = point
  let mods = PointerMods.current
  if mods.shift {
    switch handle {
    case .topLeft, .bottomRight, .topRight, .bottomLeft:
      let cx = (minX + maxX) / 2
      let cy = (minY + maxY) / 2
      let dx = p.x - cx
      let dy = p.y - cy
      let side = max(abs(dx), abs(dy))
      p = CGPoint(
        x: cx + side * (dx < 0 ? -1 : 1),
        y: cy + side * (dy < 0 ? -1 : 1)
      )
    default:
      break
    }
  }
  switch handle {
  case .topLeft:
    minX = p.x; minY = p.y
  case .topRight:
    maxX = p.x; minY = p.y
  case .bottomLeft:
    minX = p.x; maxY = p.y
  case .bottomRight:
    maxX = p.x; maxY = p.y
  default:
    break
  }
  return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).normalized
}

/// Maps between canvas-view points (SwiftUI, top-left) and image-pixel points.
struct CanvasTransform {
  var container: CGSize
  var imageSize: CGSize
  var zoom: CGFloat
  var pan: CGSize

  var fitted: CGRect {
    guard imageSize.width > 0, imageSize.height > 0 else {
      return CGRect(origin: .zero, size: container)
    }
    let pad = AnnotatorChrome.canvasInset
    let avail = CGSize(
      width: max(1, container.width - pad * 2),
      height: max(1, container.height - pad * 2)
    )
    let scale = min(avail.width / imageSize.width, avail.height / imageSize.height)
    let width = imageSize.width * scale
    let height = imageSize.height * scale
    return CGRect(
      x: (container.width - width) / 2,
      y: (container.height - height) / 2,
      width: width,
      height: height
    )
  }

  var displayed: CGRect {
    let fit = fitted
    let width = fit.width * zoom
    let height = fit.height * zoom
    return CGRect(
      x: fit.midX - width / 2 + pan.width,
      y: fit.midY - height / 2 + pan.height,
      width: width,
      height: height
    )
  }

  func toImage(_ canvasPoint: CGPoint) -> CGPoint {
    let rect = displayed
    guard rect.width > 0, rect.height > 0 else { return .zero }
    return CGPoint(
      x: (canvasPoint.x - rect.minX) / rect.width * imageSize.width,
      y: (canvasPoint.y - rect.minY) / rect.height * imageSize.height
    )
  }

  func toCanvas(_ imagePoint: CGPoint) -> CGPoint {
    let rect = displayed
    guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
    return CGPoint(
      x: rect.minX + imagePoint.x / imageSize.width * rect.width,
      y: rect.minY + imagePoint.y / imageSize.height * rect.height
    )
  }

  /// Pan that keeps `imagePoint` under `canvasPoint` at `zoom`.
  static func panKeeping(
    imagePoint: CGPoint,
    at canvasPoint: CGPoint,
    zoom: CGFloat,
    imageSize: CGSize,
    container: CGSize
  ) -> CGSize {
    let fitted = CanvasTransform(
      container: container,
      imageSize: imageSize,
      zoom: 1,
      pan: .zero
    ).fitted
    guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
    let panX = canvasPoint.x - fitted.midX
      - fitted.width * zoom * (imagePoint.x / imageSize.width - 0.5)
    let panY = canvasPoint.y - fitted.midY
      - fitted.height * zoom * (imagePoint.y / imageSize.height - 0.5)
    return CGSize(width: panX, height: panY)
  }
}

extension NSImage {
  var fullCGImage: CGImage? {
    if let rep = representations
      .compactMap({ $0 as? NSBitmapImageRep })
      .max(by: { $0.pixelsWide < $1.pixelsWide })
    {
      return rep.cgImage
    }
    guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else {
      return nil
    }
    return rep.cgImage
  }
}
