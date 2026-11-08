import AppKit
import SwiftUI

struct AnnotationCanvasView: View {
  @ObservedObject var state: AppState
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
          let boxWidth = max(48, state.textWidth * scale)
          let fontSize = max(11, state.textFont * scale)
          let measured = TextLayout.measure(
            string: state.textDraft,
            fontSize: fontSize,
            width: boxWidth
          )
          let boxHeight = min(360, max(measured.height + 4, fontSize * 1.35))
          let chrome = textChrome(state.textColor)
          HStack(alignment: .top, spacing: 0) {
            TextBoxEditor(
              text: $state.textDraft,
              fontSize: fontSize,
              color: NSColor(state.textColor.swatch)
            )
            .frame(width: boxWidth, height: boxHeight)
            TextWidthHandle(color: chrome.border) {
              state.textWidth = max(36, state.textWidth + $0 / max(scale, 0.01))
              state.statusMessage = String(format: "Width %.0f", state.textWidth)
            }
          }
          .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
              .fill(chrome.fill)
          )
          .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
              .strokeBorder(chrome.border, lineWidth: 1.5)
          )
          .offset(x: displayOrigin.x, y: displayOrigin.y)
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
    switch stage {
    case .checker: return .clear
    case .void: return Color.white.opacity(0.16)
    case .chrome: return Color.primary.opacity(0.18)
    }
  }

  private func textChrome(_ color: AnnotationColor) -> (fill: Color, border: Color) {
    switch color {
    case .white, .yellow, .cyan, .mint:
      return (Color.black.opacity(0.78), color.swatch)
    default:
      return (Color.white.opacity(0.94), color.swatch)
    }
  }

  private func dragGesture() -> some Gesture {
    DragGesture(minimumDistance: 0, coordinateSpace: .local)
      .onChanged { value in
        state.lastCanvasPoint = value.location
        if state.isTyping { return }

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
        if state.isTyping, let origin = state.textOrigin {
          let transform = state.canvasTransform()
          let boxOrigin = transform.toCanvas(origin)
          let scale = transform.displayed.width / max(state.image.size.width, 1)
          let box = CGRect(
            x: boxOrigin.x - 8,
            y: boxOrigin.y - 8,
            width: state.textWidth * scale + 28,
            height: 420
          )
          if !box.contains(value.location) {
            state.commitTextIfNeeded(cancel: false)
          }
          return
        }

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

        state.endPointer(at: imagePoint, clickCount: clicks)
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
    case let .textBox(origin, width):
      let scaleX = viewSize.width / max(imageSize.width, 1)
      return .textBox(
        origin: imageToView(origin, imageSize: imageSize, viewSize: viewSize),
        width: width * scaleX
      )
    case let .slice(start, current, axis):
      return .slice(
        start: imageToView(start, imageSize: imageSize, viewSize: viewSize),
        current: imageToView(current, imageSize: imageSize, viewSize: viewSize),
        axis: axis
      )
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
    case let .redact(rect, style):
      return .redact(scale(rect: rect.normalized, from: imageSize, to: viewSize), style: style)
    case let .arrow(start, end, control, headed):
      return .arrow(
        start: imageToView(start, imageSize: imageSize, viewSize: viewSize),
        end: imageToView(end, imageSize: imageSize, viewSize: viewSize),
        control: control.map { imageToView($0, imageSize: imageSize, viewSize: viewSize) },
        headed: headed
      )
    case let .path(points):
      return .path(points.map { imageToView($0, imageSize: imageSize, viewSize: viewSize) })
    case let .text(origin, width, fontSize, string):
      let scaleX = viewSize.width / max(imageSize.width, 1)
      let scaleY = viewSize.height / max(imageSize.height, 1)
      return .text(
        origin: imageToView(origin, imageSize: imageSize, viewSize: viewSize),
        width: width * scaleX,
        fontSize: fontSize * min(scaleX, scaleY),
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

/// Multiline text box with no extra insets, so the glyphs line up with the mark.
private struct TextBoxEditor: NSViewRepresentable {
  @Binding var text: String
  var fontSize: CGFloat
  var color: NSColor

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text)
  }

  func makeNSView(context: Context) -> NSScrollView {
    let scroll = NSTextView.scrollableTextView()
    scroll.drawsBackground = false
    scroll.hasVerticalScroller = false
    scroll.hasHorizontalScroller = false
    scroll.borderType = .noBorder
    scroll.autohidesScrollers = true

    let textView = scroll.documentView as! NSTextView
    textView.isRichText = false
    textView.importsGraphics = false
    textView.allowsUndo = true
    textView.drawsBackground = false
    textView.focusRingType = .none
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.textContainerInset = NSSize(width: 0, height: 2)
    textView.textContainer?.lineFragmentPadding = 0
    textView.textContainer?.widthTracksTextView = true
    textView.isHorizontallyResizable = false
    textView.isVerticallyResizable = true
    textView.font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
    textView.textColor = color
    textView.insertionPointColor = color
    textView.string = text
    textView.delegate = context.coordinator
    context.coordinator.textView = textView

    DispatchQueue.main.async {
      textView.window?.makeFirstResponder(textView)
    }
    return scroll
  }

  func updateNSView(_ scroll: NSScrollView, context: Context) {
    guard let textView = scroll.documentView as? NSTextView else { return }
    if textView.string != text {
      let selected = textView.selectedRange()
      textView.string = text
      let length = (text as NSString).length
      textView.setSelectedRange(NSRange(location: min(selected.location, length), length: 0))
    }
    let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
    if textView.font != font { textView.font = font }
    if textView.textColor != color {
      textView.textColor = color
      textView.insertionPointColor = color
    }
  }

  final class Coordinator: NSObject, NSTextViewDelegate {
    @Binding var text: String
    weak var textView: NSTextView?

    init(text: Binding<String>) {
      _text = text
    }

    func textDidChange(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView else { return }
      if text != textView.string {
        text = textView.string
      }
    }
  }
}

/// Right-edge grip. Dragging changes the wrap width while typing.
private struct TextWidthHandle: View {
  var color: Color
  var onDrag: (CGFloat) -> Void

  @State private var origin: CGFloat?

  var body: some View {
    RoundedRectangle(cornerRadius: 2, style: .continuous)
      .fill(color)
      .frame(width: 7)
      .padding(.vertical, 6)
      .padding(.trailing, 4)
      .contentShape(Rectangle())
      .onHover { hovering in
        if hovering {
          NSCursor.resizeLeftRight.set()
        } else {
          NSCursor.arrow.set()
        }
      }
      .highPriorityGesture(
        DragGesture(minimumDistance: 1)
          .onChanged { value in
            let previous = origin ?? 0
            onDrag(value.translation.width - previous)
            origin = value.translation.width
          }
          .onEnded { _ in
            origin = nil
          }
      )
      .help("Drag to change the wrap width")
  }
}
