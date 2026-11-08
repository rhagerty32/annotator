import AppKit
import SwiftUI

struct AnnotationOverlay: View {
  let annotations: [Annotation]
  let draft: Draft?
  let tool: Tool
  var selectedID: UUID? = nil
  var draftColor: AnnotationColor = .red
  var defaultStroke: CGFloat = 2.5
  var strokeScale: CGFloat = 1
  var selectionColor: Color = Color(red: 0.35, green: 0.75, blue: 1.0)
  var sourceImage: NSImage? = nil
  var imageSize: CGSize = .zero
  var hideID: UUID? = nil

  var body: some View {
    Canvas { context, size in
      let spots = annotations.filter {
        if case .spotlight = $0.kind { return $0.id != hideID }
        return false
      }
      if !spots.isEmpty {
        drawSpotlights(spots, canvasSize: size, in: &context)
      }
      for annotation in annotations where annotation.id != hideID {
        if case .spotlight = annotation.kind { continue }
        draw(annotation, canvasSize: size, in: &context)
      }
      if let draft {
        drawDraft(draft, color: draftColor.swatch, canvasSize: size, in: &context)
      }
      if let selectedID,
         let selected = annotations.first(where: { $0.id == selectedID })
      {
        drawSelection(selected, in: &context)
      }
    }
    .allowsHitTesting(false)
  }

  private func width(for annotation: Annotation) -> CGFloat {
    max(1, annotation.strokeWidth * strokeScale)
  }

  private var draftWidth: CGFloat {
    max(1, defaultStroke * strokeScale)
  }

  private func draw(
    _ annotation: Annotation,
    canvasSize: CGSize,
    in context: inout GraphicsContext
  ) {
    let color = annotation.color.swatch
    let stroke = width(for: annotation)
    switch annotation.kind {
    case let .rectangle(rect, radius):
      strokeHalo(roundedRectPath(rect, radius: radius), color: color, width: stroke, in: &context)
    case let .circle(rect):
      strokeHalo(Path(ellipseIn: rect.normalized), color: color, width: stroke, in: &context)
    case let .cross(rect):
      strokeHalo(crossPath(rect), color: color, width: stroke, in: &context)
    case let .highlight(rect):
      let r = rect.normalized
      context.fill(Path(r), with: .color(color.opacity(0.38)))
    case .spotlight:
      break
    case let .redact(rect, style):
      drawRedact(rect.normalized, style: style, canvasSize: canvasSize, in: &context)
    case let .arrow(start, end, control, headed):
      strokeArrow(
        from: start,
        to: end,
        control: control,
        headed: headed,
        width: stroke,
        in: &context,
        color: color
      )
    case let .path(points):
      guard let path = path(from: points) else { return }
      strokeHalo(path, color: color, width: stroke, in: &context, cap: .round, join: .round)
    case let .text(origin, width, fontSize, string):
      let layout = TextLayout.measure(string: string, fontSize: fontSize, width: max(36, width))
      var y = origin.y
      for line in layout.lines {
        if !line.isEmpty {
          let ink = context.resolve(
            Text(line).font(.system(size: fontSize, weight: .semibold)).foregroundStyle(color)
          )
          context.draw(ink, at: CGPoint(x: origin.x, y: y), anchor: .topLeading)
        }
        y += layout.lineHeight
      }
    case let .badge(origin, index):
      drawBadge(at: origin, index: index, color: color, stroke: stroke, in: &context)
    }
  }

  private func drawSpotlights(
    _ spots: [Annotation],
    canvasSize: CGSize,
    in context: inout GraphicsContext
  ) {
    var dim = Path()
    dim.addRect(CGRect(origin: .zero, size: canvasSize))
    for annotation in spots {
      guard case let .spotlight(rect) = annotation.kind else { continue }
      let r = rect.normalized
      dim.addRoundedRect(in: r, cornerSize: CGSize(width: 8, height: 8), style: .continuous)
    }
    context.fill(dim, with: .color(.black.opacity(0.5)), style: FillStyle(eoFill: true))
    for annotation in spots {
      guard case let .spotlight(rect) = annotation.kind else { continue }
      let r = rect.normalized
      let hole = Path(roundedRect: r, cornerRadius: 8, style: .continuous)
      context.stroke(hole, with: .color(annotation.color.swatch.opacity(0.85)), lineWidth: 1.5)
    }
  }

  private func drawDraft(
    _ draft: Draft,
    color: Color,
    canvasSize: CGSize,
    in context: inout GraphicsContext
  ) {
    let mods = PointerMods.current
    let stroke = draftWidth
    switch draft {
    case let .shape(start, current):
      if tool.drawsLine {
        let snapped = snapArrow(from: start, to: current, constrain: mods.shift)
        strokeArrow(
          from: snapped.0,
          to: snapped.1,
          control: nil,
          headed: tool == .line ? mods.option : !mods.option,
          width: stroke,
          in: &context,
          color: color
        )
      } else {
        let rect = shapeRect(from: start, to: current, mods: mods)
        if tool == .crop {
          drawCropDraft(rect, canvasSize: canvasSize, in: &context)
        } else if tool == .highlight {
          context.fill(Path(rect), with: .color(color.opacity(0.28)))
        } else if tool == .spotlight {
          var dim = Path()
          dim.addRect(CGRect(origin: .zero, size: canvasSize))
          dim.addRoundedRect(in: rect, cornerSize: CGSize(width: 8, height: 8), style: .continuous)
          context.fill(dim, with: .color(.black.opacity(0.4)), style: FillStyle(eoFill: true))
          context.stroke(
            Path(roundedRect: rect, cornerRadius: 8, style: .continuous),
            with: .color(color.opacity(0.9)),
            lineWidth: 1.5
          )
        } else if tool == .redact {
          context.fill(Path(rect), with: .color(.black.opacity(0.4)))
          context.stroke(
            Path(rect),
            with: .color(.white.opacity(0.85)),
            style: StrokeStyle(lineWidth: 1, dash: [5, 4])
          )
        } else if tool == .circle {
          strokeHalo(Path(ellipseIn: rect), color: color, width: stroke, in: &context)
        } else if tool == .cross {
          strokeHalo(crossPath(rect), color: color, width: stroke, in: &context)
        } else {
          strokeHalo(Path(rect), color: color, width: stroke, in: &context)
        }
      }
    case let .path(points):
      guard let path = path(from: points) else { return }
      strokeHalo(path, color: color, width: stroke, in: &context, cap: .round, join: .round)
    case let .textBox(origin, width):
      let fontSize = max(13, draftWidth * 7)
      let line = TextLayout.measure(string: "", fontSize: fontSize, width: max(width, 8)).lineHeight
      let rect = CGRect(x: origin.x, y: origin.y, width: max(width, 2), height: line)
      context.stroke(
        Path(rect),
        with: .color(color.opacity(0.9)),
        style: StrokeStyle(lineWidth: 1.25, dash: [5, 3])
      )
    case let .slice(start, current, axis):
      drawSliceDraft(start: start, current: current, axis: axis, canvasSize: canvasSize, in: &context)
    }
  }

  private var sliceInk: Color { Color(red: 1, green: 0.23, blue: 0.19) }

  private func drawSliceDraft(
    start: CGPoint,
    current: CGPoint,
    axis: SliceAxis?,
    canvasSize: CGSize,
    in context: inout GraphicsContext
  ) {
    guard let axis else {
      let dot = CGRect(x: start.x - 3.5, y: start.y - 3.5, width: 7, height: 7)
      context.fill(Path(ellipseIn: dot), with: .color(sliceInk))
      return
    }

    let rect: CGRect
    let imageRemoved: CGFloat
    switch axis {
    case .horizontal:
      let span = sliceSpan(from: start.x, to: current.x, limit: canvasSize.width)
      rect = CGRect(x: span.lo, y: 0, width: span.hi - span.lo, height: canvasSize.height)
      imageRemoved = canvasSize.width > 0
        ? (span.hi - span.lo) / canvasSize.width * imageSize.width
        : 0
    case .vertical:
      let span = sliceSpan(from: start.y, to: current.y, limit: canvasSize.height)
      rect = CGRect(x: 0, y: span.lo, width: canvasSize.width, height: span.hi - span.lo)
      imageRemoved = canvasSize.height > 0
        ? (span.hi - span.lo) / canvasSize.height * imageSize.height
        : 0
    }
    guard rect.width > 0.5, rect.height > 0.5 else { return }

    context.fill(Path(rect), with: .color(sliceInk.opacity(0.34)))
    var edges = Path()
    switch axis {
    case .horizontal:
      edges.move(to: CGPoint(x: rect.minX, y: rect.minY))
      edges.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
      edges.move(to: CGPoint(x: rect.maxX, y: rect.minY))
      edges.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    case .vertical:
      edges.move(to: CGPoint(x: rect.minX, y: rect.minY))
      edges.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
      edges.move(to: CGPoint(x: rect.minX, y: rect.maxY))
      edges.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    }
    context.stroke(edges, with: .color(.white), lineWidth: 1.5)

    let shortSide = min(rect.width, rect.height)
    guard shortSide >= 28 else { return }
    let caption = "\(Int(imageRemoved.rounded())) px"
    let box = CGRect(
      x: rect.midX - CGFloat(caption.count) * 3.6 - 8,
      y: rect.midY - 9,
      width: CGFloat(caption.count) * 7.2 + 16,
      height: 18
    )
    context.fill(Path(roundedRect: box, cornerRadius: 4), with: .color(.black.opacity(0.72)))
    let label = context.resolve(
      Text(caption)
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundStyle(.white)
    )
    context.draw(label, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
  }

  private func drawCropDraft(_ rect: CGRect, canvasSize: CGSize, in context: inout GraphicsContext) {
    var dim = Path()
    dim.addRect(CGRect(origin: .zero, size: canvasSize))
    dim.addRect(rect)
    context.fill(dim, with: .color(.black.opacity(0.45)), style: FillStyle(eoFill: true))
    context.stroke(
      Path(rect),
      with: .color(.white),
      style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
    )
  }

  private func drawRedact(
    _ rect: CGRect,
    style: RedactStyle,
    canvasSize: CGSize,
    in context: inout GraphicsContext
  ) {
    guard let sourceImage, imageSize.width > 0, imageSize.height > 0 else {
      context.fill(Path(rect), with: .color(.black.opacity(0.55)))
      return
    }
    let imageRect = CGRect(
      x: rect.minX / canvasSize.width * imageSize.width,
      y: rect.minY / canvasSize.height * imageSize.height,
      width: rect.width / canvasSize.width * imageSize.width,
      height: rect.height / canvasSize.height * imageSize.height
    )
    let painted: NSImage? = style == .blur
      ? PixelateService.blur(source: sourceImage, imageRect: imageRect)
      : PixelateService.mosaic(source: sourceImage, imageRect: imageRect)
    if let painted {
      let resolved = context.resolve(Image(nsImage: painted).resizable())
      context.draw(resolved, in: rect)
    } else {
      context.fill(Path(rect), with: .color(.black.opacity(0.55)))
    }
  }

  private func drawBadge(
    at origin: CGPoint,
    index: Int,
    color: Color,
    stroke: CGFloat,
    in context: inout GraphicsContext
  ) {
    let radius = max(12, stroke * 5)
    let rect = CGRect(x: origin.x - radius, y: origin.y - radius, width: radius * 2, height: radius * 2)
    let circle = Path(ellipseIn: rect)
    context.fill(circle, with: .color(color))
    let label = context.resolve(
      Text("\(index)")
        .font(.system(size: max(11, radius * 0.9), weight: .bold, design: .rounded))
        .foregroundStyle(.white)
    )
    context.draw(label, at: origin, anchor: .center)
  }

  private func drawSelection(_ annotation: Annotation, in context: inout GraphicsContext) {
    if case .arrow = annotation.kind {
      // Handles only — a dashed box around a shaft is noise.
    } else {
      let bounds = annotation.boundingRect
      context.stroke(
        Path(bounds),
        with: .color(selectionColor.opacity(0.9)),
        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
      )
    }

    for handle in annotation.resizeHandles {
      guard let point = annotation.handlePoint(handle) else { continue }
      if handle == .arrowCurve || handle == .rectRadius {
        let size: CGFloat = 9
        let rect = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
        context.fill(Path(ellipseIn: rect), with: .color(.white))
        context.stroke(Path(ellipseIn: rect), with: .color(selectionColor), lineWidth: 1.5)
      } else if handle == .textWidth {
        let rect = CGRect(x: point.x - 3, y: point.y - 9, width: 6, height: 18)
        context.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(.white))
        context.stroke(Path(roundedRect: rect, cornerRadius: 3), with: .color(selectionColor), lineWidth: 1.5)
      } else {
        let size: CGFloat = 8
        let rect = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
        context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(.white))
        context.stroke(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(selectionColor), lineWidth: 1.5)
      }
    }
  }

  private func strokeHalo(
    _ path: Path,
    color: Color,
    width: CGFloat,
    in context: inout GraphicsContext,
    cap: CGLineCap = .round,
    join: CGLineJoin = .round
  ) {
    context.stroke(
      path,
      with: .color(color),
      style: StrokeStyle(lineWidth: width, lineCap: cap, lineJoin: join)
    )
  }

  private func strokeArrow(
    from start: CGPoint,
    to end: CGPoint,
    control: CGPoint?,
    headed: Bool,
    width: CGFloat,
    in context: inout GraphicsContext,
    color: Color
  ) {
    let c = control ?? midpoint(start, end)
    var shaft = Path()
    shaft.move(to: start)
    shaft.addQuadCurve(to: end, control: c)
    strokeHalo(shaft, color: color, width: width, in: &context)

    guard headed else { return }

    var dx = end.x - c.x
    var dy = end.y - c.y
    if hypot(dx, dy) < 0.001 {
      dx = end.x - start.x
      dy = end.y - start.y
    }
    let angle = atan2(dy, dx)
    let head: CGFloat = max(12, width * 5)
    let a1 = angle + .pi - .pi / 7
    let a2 = angle + .pi + .pi / 7
    var headPath = Path()
    headPath.move(to: end)
    headPath.addLine(to: CGPoint(x: end.x + head * cos(a1), y: end.y + head * sin(a1)))
    headPath.move(to: end)
    headPath.addLine(to: CGPoint(x: end.x + head * cos(a2), y: end.y + head * sin(a2)))
    strokeHalo(headPath, color: color, width: width, in: &context)
  }

  private func path(from points: [CGPoint]) -> Path? {
    guard let first = points.first else { return nil }
    var path = Path()
    path.move(to: first)
    for point in points.dropFirst() {
      path.addLine(to: point)
    }
    return path
  }
}
