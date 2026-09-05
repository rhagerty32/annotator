import AppKit
import SwiftUI

struct AnnotationCanvasView: View {
  @ObservedObject var state: AppState
  @FocusState private var textFocused: Bool
  @State private var inputMonitor: Any?
  @State private var panDragOrigin: CGSize?

  var body: some View {
    GeometryReader { geo in
      let transform = CanvasTransform(
        container: geo.size,
        imageSize: state.image.size,
        zoom: state.zoom,
        pan: state.pan
      )
      let displayed = transform.displayed
      let scale = displayed.width / max(state.image.size.width, 1)
      let stroke = max(1, state.strokeWidth * scale)

      ZStack(alignment: .topLeading) {
        CanvasStageBackground(stage: state.stage, canvasSize: geo.size)

        Canvas { context, _ in
          if let cgImage = state.cgImage {
            context.draw(Image(decorative: cgImage, scale: 1), in: displayed)
          }
        }
        .frame(width: geo.size.width, height: geo.size.height)
        .allowsHitTesting(false)

        Rectangle()
          .strokeBorder(shotStroke(for: state.stage), lineWidth: 1)
          .frame(width: displayed.width, height: displayed.height)
          .position(x: displayed.midX, y: displayed.midY)
          .shadow(
            color: state.stage == .checker ? .black.opacity(0.55) : .clear,
            radius: state.stage == .checker ? 22 : 0,
            x: 0,
            y: state.stage == .checker ? 10 : 0
          )
          .allowsHitTesting(false)

        AnnotationOverlay(
          annotations: scaledAnnotations(
            state.annotations,
            from: state.image.size,
            to: displayed.size
          ),
          draft: scaledDraft(state.draft, from: state.image.size, to: displayed.size),
          tool: state.tool,
          selectedID: state.selectedID,
          draftColor: state.activeColor,
          defaultStroke: state.strokeWidth,
          strokeScale: scale,
          sourceImage: state.image,
          imageSize: state.image.size,
          hideID: state.editingID
        )
        .frame(width: displayed.width, height: displayed.height)
        .position(x: displayed.midX, y: displayed.midY)
        .allowsHitTesting(false)

        if state.isTyping, let origin = state.textOrigin {
          let displayOrigin = transform.toCanvas(origin)
          TextField("", text: $state.textDraft)
            .textFieldStyle(.plain)
            .font(.system(size: max(14, stroke * 7), weight: .semibold))
            .foregroundStyle(state.activeColor.swatch)
            .padding(6)
            .background(Color.black.opacity(0.55))
            .cornerRadius(4)
            .frame(width: max(140, displayed.width * 0.35), alignment: .leading)
            .offset(x: displayOrigin.x, y: displayOrigin.y)
            .focused($textFocused)
            .onSubmit { state.commitTextIfNeeded(cancel: false) }
        }
      }
      .frame(width: geo.size.width, height: geo.size.height)
      .clipped()
      .contentShape(Rectangle())
      .onContinuousHover { phase in
        switch phase {
        case let .active(point):
          state.lastCanvasPoint = point
          state.cursorInsideCanvas = true
        case .ended:
          state.cursorInsideCanvas = false
        }
      }
      .gesture(dragGesture())
      .onChange(of: state.isTyping) { _, typing in
        textFocused = typing
      }
      .onChange(of: state.spaceHeld) { _, held in
        if held, !state.isTyping {
          NSCursor.openHand.set()
        } else {
          NSCursor.arrow.set()
        }
      }
      .onAppear {
        state.canvasSize = geo.size
        if state.lastCanvasPoint == .zero {
          state.lastCanvasPoint = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        installInputMonitor()
      }
      .onDisappear { removeInputMonitor() }
      .onChange(of: geo.size) { _, newSize in
        state.canvasSize = newSize
      }
    }
  }

  private func shotStroke(for stage: CanvasStage) -> Color {
    stage == .checker ? Color.clear : Color.white.opacity(0.16)
  }

  private func dragGesture() -> some Gesture {
    DragGesture(minimumDistance: 0, coordinateSpace: .local)
      .onChanged { value in
        state.lastCanvasPoint = value.location

        if state.spaceHeld {
          if panDragOrigin == nil {
            panDragOrigin = state.pan
            NSCursor.closedHand.set()
          }
          if let origin = panDragOrigin, state.zoom > 1 {
            state.pan = CGSize(
              width: origin.width + value.translation.width,
              height: origin.height + value.translation.height
            )
          }
          return
        }

        let imagePoint = state.canvasTransform().toImage(value.location)
        let displayed = state.canvasTransform().displayed
        let handleTol = 12 * state.image.size.width / max(displayed.width, 1)

        if state.tool.placesOnClick {
          return
        }

        if state.dragSession == nil && state.draft == nil {
          state.beginPointer(at: imagePoint, handleHitTolerance: handleTol)
        } else {
          state.updatePointer(to: imagePoint)
        }
      }
      .onEnded { value in
        state.lastCanvasPoint = value.location

        if panDragOrigin != nil {
          panDragOrigin = nil
          if state.spaceHeld {
            NSCursor.openHand.set()
          }
          return
        }

        let imagePoint = state.canvasTransform().toImage(value.location)
        let displayed = state.canvasTransform().displayed
        let handleTol = 12 * state.image.size.width / max(displayed.width, 1)
        let traveled = hypot(value.translation.width, value.translation.height)
        let clicks = NSApp.currentEvent?.clickCount ?? 1

        if state.tool.placesOnClick {
          if traveled < 4 {
            state.handleClick(at: imagePoint, handleHitTolerance: handleTol)
          }
          return
        }

        if state.tool == .select, clicks >= 2, traveled < 4 {
          state.handleDoubleClick(at: imagePoint)
          return
        }

        if state.tool == .select, traveled < 4, state.dragSession == nil {
          state.handleClick(at: imagePoint, handleHitTolerance: handleTol)
          return
        }

        state.endPointer(at: imagePoint)
      }
  }

  private func installInputMonitor() {
    removeInputMonitor()
    inputMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { event in
      guard !state.isTyping, !state.showHelp, !state.showToolPalette else { return event }
      guard state.cursorInsideCanvas, state.canvasSize.width > 1 else { return event }

      if event.type == .magnify {
        state.zoom(by: 1 + event.magnification, around: state.lastCanvasPoint)
        return nil
      }

      if event.type == .scrollWheel {
        if !event.momentumPhase.isEmpty { return nil }
        let dy = event.hasPreciseScrollingDeltas
          ? event.scrollingDeltaY
          : event.scrollingDeltaY * 12
        guard abs(dy) > 0.1 else { return event }
        state.zoom(by: pow(1.006, dy), around: state.lastCanvasPoint)
        return nil
      }

      return event
    }
  }

  private func removeInputMonitor() {
    if let inputMonitor {
      NSEvent.removeMonitor(inputMonitor)
      self.inputMonitor = nil
    }
  }

  private func scaledAnnotations(
    _ annotations: [Annotation],
    from imageSize: CGSize,
    to viewSize: CGSize
  ) -> [Annotation] {
    annotations.map { annotation in
      Annotation(
        id: annotation.id,
        kind: scale(kind: annotation.kind, from: imageSize, to: viewSize),
        color: annotation.color,
        strokeWidth: annotation.strokeWidth
      )
    }
  }

  private func scaledDraft(_ draft: Draft?, from imageSize: CGSize, to viewSize: CGSize) -> Draft? {
    guard let draft else { return nil }
    switch draft {
    case let .shape(start, current):
      return .shape(
        start: imageToView(start, imageSize: imageSize, viewSize: viewSize),
        current: imageToView(current, imageSize: imageSize, viewSize: viewSize)
      )
    case let .path(points):
      return .path(points.map { imageToView($0, imageSize: imageSize, viewSize: viewSize) })
    case let .textPlacement(origin):
      return .textPlacement(imageToView(origin, imageSize: imageSize, viewSize: viewSize))
    }
  }

  private func scale(kind: Annotation.Kind, from imageSize: CGSize, to viewSize: CGSize) -> Annotation.Kind {
    switch kind {
    case let .rectangle(rect, radius):
      return .rectangle(
        scale(rect: rect.normalized, from: imageSize, to: viewSize),
        radius: radius / max(imageSize.width, 1) * viewSize.width
      )
    case let .circle(rect):
      return .circle(scale(rect: rect.normalized, from: imageSize, to: viewSize))
    case let .cross(rect):
      return .cross(scale(rect: rect.normalized, from: imageSize, to: viewSize))
    case let .highlight(rect):
      return .highlight(scale(rect: rect.normalized, from: imageSize, to: viewSize))
    case let .spotlight(rect):
      return .spotlight(scale(rect: rect.normalized, from: imageSize, to: viewSize))
    case let .redact(rect):
      return .redact(scale(rect: rect.normalized, from: imageSize, to: viewSize))
    case let .arrow(start, end, control, headed):
      return .arrow(
        start: imageToView(start, imageSize: imageSize, viewSize: viewSize),
        end: imageToView(end, imageSize: imageSize, viewSize: viewSize),
        control: control.map { imageToView($0, imageSize: imageSize, viewSize: viewSize) },
        headed: headed
      )
    case let .path(points):
      return .path(points.map { imageToView($0, imageSize: imageSize, viewSize: viewSize) })
    case let .text(origin, string):
      return .text(
        origin: imageToView(origin, imageSize: imageSize, viewSize: viewSize),
        string: string
      )
    case let .badge(origin, index):
      return .badge(
        origin: imageToView(origin, imageSize: imageSize, viewSize: viewSize),
        index: index
      )
    }
  }

  private func scale(rect: CGRect, from imageSize: CGSize, to viewSize: CGSize) -> CGRect {
    let origin = imageToView(rect.origin, imageSize: imageSize, viewSize: viewSize)
    let corner = imageToView(
      CGPoint(x: rect.maxX, y: rect.maxY),
      imageSize: imageSize,
      viewSize: viewSize
    )
    return CGRect(
      x: origin.x,
      y: origin.y,
      width: corner.x - origin.x,
      height: corner.y - origin.y
    ).normalized
  }

  private func imageToView(_ point: CGPoint, imageSize: CGSize, viewSize: CGSize) -> CGPoint {
    guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
    return CGPoint(
      x: point.x / imageSize.width * viewSize.width,
      y: point.y / imageSize.height * viewSize.height
    )
  }
}

/// Stage fill, optional checkerboard.
private struct CanvasStageBackground: View {
  let stage: CanvasStage
  let canvasSize: CGSize

  var body: some View {
    ZStack {
      stage.fill

      if stage == .checker {
        CheckerboardBackground()
      }
    }
    .frame(width: canvasSize.width, height: canvasSize.height)
    .allowsHitTesting(false)
  }
}

/// Transparency-style checkerboard behind the screenshot.
private struct CheckerboardBackground: View {
  var tile: CGFloat = 14
  private let dark = Color(red: 0.17, green: 0.17, blue: 0.18)
  private let light = Color(red: 0.24, green: 0.24, blue: 0.25)

  var body: some View {
    Canvas { context, size in
      context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(dark))
      let cols = Int(ceil(size.width / tile))
      let rows = Int(ceil(size.height / tile))
      for row in 0..<rows {
        for col in 0..<cols where (row + col).isMultiple(of: 2) {
          let rect = CGRect(
            x: CGFloat(col) * tile,
            y: CGFloat(row) * tile,
            width: tile,
            height: tile
          )
          context.fill(Path(rect), with: .color(light))
        }
      }
    }
    .allowsHitTesting(false)
  }
}
