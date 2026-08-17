import AppKit
import SwiftUI

@MainActor
final class AppState: ObservableObject {
  @Published var image: NSImage
  @Published var annotations: [Annotation] = []
  @Published var tool: Tool = .rectangle
  @Published var activeColor: AnnotationColor = .red
  @Published var strokeWidth: CGFloat
  @Published var arrowHeaded = true
  @Published var draft: Draft?
  @Published var isTyping = false
  @Published var textDraft = ""
  @Published var textOrigin: CGPoint?
  @Published var selectedID: UUID?
  @Published var editingID: UUID?
  @Published var showHelp = false
  @Published var showSettings = false
  @Published var stage: CanvasStage {
    didSet { UserDefaults.standard.set(stage.rawValue, forKey: Self.stageDefaultsKey) }
  }
  @Published var zoom: CGFloat = 1
  @Published var pan: CGSize = .zero
  @Published var spaceHeld = false
  @Published var statusMessage = "V R C A D T · H N B X · 1–0 · [ ] stroke · S save"

  let imageURL: URL?
  private(set) var dragSession: DragSession?

  /// Canvas view size in SwiftUI points. Not published — updated from the view.
  var canvasSize: CGSize = .zero
  /// Last pointer location in canvas space. Used to zoom toward the cursor.
  var lastCanvasPoint: CGPoint = .zero
  var cursorInsideCanvas = false

  private var undoStack: [HistoryFrame] = []
  private var redoStack: [HistoryFrame] = []
  private var didPushForGesture = false
  private var lastPointer: CGPoint?

  init(image: NSImage, imageURL: URL? = nil) {
    self.image = image
    self.imageURL = imageURL
    self.strokeWidth = max(2.5, image.size.width * 0.0025)
    let stored = UserDefaults.standard.string(forKey: Self.stageDefaultsKey) ?? ""
    self.stage = CanvasStage(rawValue: stored) ?? .void
  }

  private static let stageDefaultsKey = "annotator.canvasStage"

  var selectedAnnotation: Annotation? {
    guard let selectedID else { return nil }
    return annotations.first { $0.id == selectedID }
  }

  func setColor(_ color: AnnotationColor) {
    activeColor = color
    if let selectedID,
       let index = annotations.firstIndex(where: { $0.id == selectedID })
    {
      pushHistory()
      annotations[index].color = color
    }
  }

  func canvasTransform() -> CanvasTransform {
    CanvasTransform(
      container: canvasSize,
      imageSize: image.size,
      zoom: zoom,
      pan: pan
    )
  }

  func resetView() {
    zoom = 1
    pan = .zero
  }

  func nudgeZoom(factor: CGFloat) {
    zoom(by: factor, around: lastCanvasPoint)
  }

  func zoom(by factor: CGFloat, around canvasPoint: CGPoint) {
    let transform = canvasTransform()
    let anchor = canvasSize.width > 1 ? canvasPoint : CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
    let imagePoint = transform.toImage(anchor)
    let newZoom = min(max(zoom * factor, AnnotatorChrome.minZoom), AnnotatorChrome.maxZoom)
    let newPan = CanvasTransform.panKeeping(
      imagePoint: imagePoint,
      at: anchor,
      zoom: newZoom,
      imageSize: image.size,
      container: canvasSize.width > 1 ? canvasSize : transform.container
    )
    setZoom(newZoom, pan: newPan)
  }

  func setZoom(_ newZoom: CGFloat, pan newPan: CGSize) {
    let clamped = min(max(newZoom, AnnotatorChrome.minZoom), AnnotatorChrome.maxZoom)
    if clamped <= AnnotatorChrome.minZoom + 0.001 {
      zoom = AnnotatorChrome.minZoom
      pan = .zero
    } else {
      zoom = clamped
      pan = newPan
    }
  }

  func nudgeStroke(_ delta: CGFloat) {
    guard !isTyping else { return }
    if let selectedID, let index = annotations.firstIndex(where: { $0.id == selectedID }) {
      pushHistory()
      let next = min(28, max(1, annotations[index].strokeWidth + delta))
      annotations[index].strokeWidth = next
      statusMessage = String(format: "Stroke %.0f pt", next)
      return
    }
    strokeWidth = min(28, max(1, strokeWidth + delta))
    statusMessage = String(format: "Stroke %.0f pt", strokeWidth)
  }

  func nudgeSelection(dx: CGFloat, dy: CGFloat) {
    guard !isTyping, let selected = selectedAnnotation else { return }
    pushHistory()
    replace(id: selected.id, with: selected.translated(by: CGPoint(x: dx, y: dy)))
  }

  func duplicateSelection() {
    guard !isTyping, let selected = selectedAnnotation else { return }
    pushHistory()
    let offset = max(12, image.size.width * 0.012)
    let dup = Annotation(
      kind: selected.kind,
      color: selected.color,
      strokeWidth: selected.strokeWidth
    ).translated(by: CGPoint(x: offset, y: offset))
    annotations.append(dup)
    selectedID = dup.id
    statusMessage = "Duplicated · ⌥-drag also duplicates"
  }

  func bringForward() {
    guard !isTyping, let selectedID,
          let index = annotations.firstIndex(where: { $0.id == selectedID }),
          index < annotations.count - 1
    else { return }
    pushHistory()
    annotations.swapAt(index, index + 1)
    statusMessage = "Brought forward"
  }

  func sendBackward() {
    guard !isTyping, let selectedID,
          let index = annotations.firstIndex(where: { $0.id == selectedID }),
          index > 0
    else { return }
    pushHistory()
    annotations.swapAt(index, index - 1)
    statusMessage = "Sent back"
  }

  func toggleArrowHead() {
    guard !isTyping else { return }
    if let selectedID,
       let index = annotations.firstIndex(where: { $0.id == selectedID }),
       case let .arrow(start, end, control, headed) = annotations[index].kind
    {
      pushHistory()
      annotations[index].kind = .arrow(start: start, end: end, control: control, headed: !headed)
      statusMessage = headed ? "Line" : "Arrowhead on"
      return
    }
    arrowHeaded.toggle()
    statusMessage = arrowHeaded ? "Arrows with heads" : "Lines (no head) · L toggles"
  }

  func sampleColor(at point: CGPoint) {
    guard let swatch = ImageSampler.swatch(in: image, at: point) else { return }
    activeColor = swatch
    statusMessage = "Sampled \(swatch.rawValue)"
  }

  func selectTool(_ tool: Tool) {
    guard !isTyping else { return }
    commitTextIfNeeded(cancel: true)
    self.tool = tool
    draft = nil
    dragSession = nil
    if tool != .select {
      selectedID = nil
    }
    statusMessage = status(for: tool)
  }

  func beginPointer(at point: CGPoint, handleHitTolerance: CGFloat) {
    guard !isTyping else { return }
    lastPointer = point

    if tool == .select {
      if PointerMods.current.option, hitTest(point) == nil {
        sampleColor(at: point)
        selectedID = nil
        dragSession = nil
        return
      }
      beginSelect(at: point, handleHitTolerance: handleHitTolerance)
      return
    }

    if let selected = selectedAnnotation {
      if tool == .arrow, case .arrow = selected.kind,
         grabSelected(selected, at: point, handleHitTolerance: handleHitTolerance, allowMove: true)
      {
        return
      }
      if tool == .rectangle, case .rectangle = selected.kind,
         grabSelected(selected, at: point, handleHitTolerance: handleHitTolerance, allowMove: false)
      {
        return
      }
      if tool == .spotlight, case .spotlight = selected.kind,
         grabSelected(selected, at: point, handleHitTolerance: handleHitTolerance, allowMove: false)
      {
        return
      }
    }

    selectedID = nil
    switch tool {
    case .rectangle, .circle, .arrow, .highlight, .spotlight, .redact, .crop:
      draft = .shape(start: point, current: point)
      dragSession = .draw
    case .draw:
      draft = .path([point])
      dragSession = .draw
    case .text, .numbered, .select:
      break
    }
  }

  func updatePointer(to point: CGPoint) {
    guard !isTyping else { return }
    lastPointer = point
    applyPointer(point)
  }

  func modifiersChanged() {
    guard let lastPointer, dragSession == .draw else { return }
    applyPointer(lastPointer)
  }

  func endPointer(at point: CGPoint) {
    guard !isTyping else { return }
    lastPointer = point

    switch dragSession {
    case .move, .resize:
      dragSession = nil
      didPushForGesture = false
      if let selected = selectedAnnotation {
        statusMessage = selectedStatus(selected)
      } else {
        statusMessage = "Selected · drag to move · ⌥-drag duplicate · ⌫ delete"
      }
    case .draw:
      commitDraw(at: point)
      dragSession = nil
      didPushForGesture = false
    case .none:
      didPushForGesture = false
    }
  }

  func handleClick(at point: CGPoint, handleHitTolerance: CGFloat) {
    guard !isTyping else {
      commitTextIfNeeded(cancel: false)
      return
    }

    if tool == .select {
      beginSelect(at: point, handleHitTolerance: handleHitTolerance)
      dragSession = nil
      return
    }

    if tool == .numbered {
      placeBadge(at: point)
      return
    }

    guard tool == .text else { return }
    selectedID = nil
    editingID = nil
    textOrigin = point
    textDraft = ""
    isTyping = true
    draft = .textPlacement(point)
    statusMessage = "Typing · Esc to finish · hotkeys paused"
  }

  func handleDoubleClick(at point: CGPoint) {
    guard !isTyping else { return }
    guard let hit = hitTest(point),
          let annotation = annotations.first(where: { $0.id == hit }),
          case .text = annotation.kind
    else { return }
    beginEditText(annotation)
  }

  func editSelectedText() {
    guard !isTyping, let selected = selectedAnnotation, case .text = selected.kind else { return }
    beginEditText(selected)
  }

  func commitTextIfNeeded(cancel: Bool) {
    guard isTyping else { return }
    let text = textDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    if cancel {
      isTyping = false
      textDraft = ""
      textOrigin = nil
      editingID = nil
      draft = nil
      statusMessage = status(for: tool)
      return
    }

    if let origin = textOrigin {
      if let editingID, let index = annotations.firstIndex(where: { $0.id == editingID }) {
        pushHistory()
        if text.isEmpty {
          annotations.remove(at: index)
          selectedID = nil
        } else {
          annotations[index].kind = .text(origin: origin, string: text)
          selectedID = editingID
        }
      } else if !text.isEmpty {
        pushHistory()
        annotations.append(Annotation(
          kind: .text(origin: origin, string: text),
          color: activeColor,
          strokeWidth: strokeWidth
        ))
      }
    }
    isTyping = false
    textDraft = ""
    textOrigin = nil
    editingID = nil
    draft = nil
    statusMessage = status(for: tool)
  }

  func deleteSelection() {
    guard !isTyping, let selectedID else { return }
    let wasBadge: Bool = {
      if case .badge = selectedAnnotation?.kind { return true }
      return false
    }()
    pushHistory()
    annotations.removeAll { $0.id == selectedID }
    self.selectedID = nil
    dragSession = nil
    if wasBadge { renumberBadges() }
    statusMessage = status(for: tool)
  }

  func clearSelection() {
    selectedID = nil
    dragSession = nil
    statusMessage = status(for: tool)
  }

  func toggleHelp() {
    commitTextIfNeeded(cancel: true)
    showSettings = false
    showHelp.toggle()
    if showHelp {
      draft = nil
      dragSession = nil
      didPushForGesture = false
      statusMessage = "Shortcuts · Esc or ? to close"
    } else {
      statusMessage = status(for: tool)
    }
  }

  func toggleSettings() {
    showHelp = false
    showSettings.toggle()
  }

  /// Returns true if Esc was handled without quitting.
  func handleEscape() -> Bool {
    if showHelp {
      showHelp = false
      statusMessage = status(for: tool)
      return true
    }
    if showSettings {
      showSettings = false
      return true
    }
    if isTyping {
      commitTextIfNeeded(cancel: false)
      return true
    }
    if selectedID != nil {
      clearSelection()
      return true
    }
    if draft != nil || dragSession != nil {
      draft = nil
      dragSession = nil
      didPushForGesture = false
      return true
    }
    return false
  }

  func undo() {
    guard !isTyping, let frame = undoStack.popLast() else { return }
    redoStack.append(snapshot())
    apply(frame)
    statusMessage = "Undo"
  }

  func redo() {
    guard !isTyping, let frame = redoStack.popLast() else { return }
    undoStack.append(snapshot())
    apply(frame)
    statusMessage = "Redo"
  }

  func copyToClipboard() {
    guard !isTyping else { return }
    let composite = CompositeExporter.render(
      image: image,
      annotations: annotations,
      strokeWidth: strokeWidth
    )
    ClipboardService.copyCompressed(composite)
    statusMessage = "Copied · S copies & closes"
  }

  func saveToDisk() {
    guard !isTyping else { return }
    let composite = CompositeExporter.render(
      image: image,
      annotations: annotations,
      strokeWidth: strokeWidth
    )
    DiskExporter.savePNG(composite)
    statusMessage = "Saved"
  }

  func saveAndQuit() {
    guard !isTyping else { return }
    copyToClipboard()
    cleanupTempFile()
    NSApp.terminate(nil)
  }

  func cancelAndQuit() {
    commitTextIfNeeded(cancel: true)
    cleanupTempFile()
    NSApp.terminate(nil)
  }

  private struct HistoryFrame {
    var annotations: [Annotation]
    var selectedID: UUID?
    var image: NSImage
    var strokeWidth: CGFloat
  }

  private func snapshot() -> HistoryFrame {
    HistoryFrame(
      annotations: annotations,
      selectedID: selectedID,
      image: image,
      strokeWidth: strokeWidth
    )
  }

  private func pushHistory() {
    redoStack.removeAll()
    undoStack.append(snapshot())
    if undoStack.count > 60 {
      undoStack.removeFirst()
    }
  }

  private func apply(_ frame: HistoryFrame) {
    let imageChanged = frame.image.size != image.size
    annotations = frame.annotations
    selectedID = frame.selectedID
    image = frame.image
    strokeWidth = frame.strokeWidth
    draft = nil
    dragSession = nil
    didPushForGesture = false
    if imageChanged {
      resetView()
    }
  }

  private func applyPointer(_ point: CGPoint) {
    switch dragSession {
    case let .move(id, startPoint, original, duplicated):
      let delta = CGPoint(x: point.x - startPoint.x, y: point.y - startPoint.y)
      let mods = PointerMods.current
      let dist = hypot(delta.x, delta.y)

      if mods.option, dist > 4, !duplicated {
        if !didPushForGesture {
          pushHistory()
          didPushForGesture = true
        }
        replace(id: original.id, with: original)
        let dup = Annotation(
          kind: original.kind,
          color: original.color,
          strokeWidth: original.strokeWidth
        )
        annotations.append(dup.translated(by: delta))
        selectedID = dup.id
        dragSession = .move(id: dup.id, startPoint: startPoint, original: dup, duplicated: true)
        return
      }

      if dist > 0.5, !didPushForGesture {
        pushHistory()
        didPushForGesture = true
      }
      replace(id: id, with: original.translated(by: delta))
    case let .resize(id, handle, original):
      if !didPushForGesture {
        pushHistory()
        didPushForGesture = true
      }
      var next = original.resized(handle: handle, to: point)
      if PointerMods.current.shift, case let .arrow(start, end, control, headed) = next.kind {
        if handle == .arrowEnd {
          let snapped = snapArrow(from: start, to: end, constrain: true)
          next.kind = .arrow(start: snapped.0, end: snapped.1, control: control, headed: headed)
        } else if handle == .arrowStart {
          let snapped = snapArrow(from: end, to: start, constrain: true)
          next.kind = .arrow(start: snapped.1, end: snapped.0, control: control, headed: headed)
        }
      }
      replace(id: id, with: next)
      reportResizeStatus(next, handle: handle)
    case .draw:
      switch draft {
      case let .shape(start, _):
        draft = .shape(start: start, current: point)
        reportDraftSize(start: start, current: point)
      case var .path(points):
        points.append(point)
        draft = .path(points)
      case .textPlacement, .none:
        break
      }
    case .none:
      break
    }
  }

  private func beginSelect(at point: CGPoint, handleHitTolerance: CGFloat) {
    if PointerMods.current.option, hitTest(point) == nil {
      sampleColor(at: point)
      selectedID = nil
      dragSession = nil
      return
    }

    if let selected = selectedAnnotation {
      if grabSelected(selected, at: point, handleHitTolerance: handleHitTolerance) {
        return
      }
    }

    if let hit = hitTest(point) {
      selectedID = hit
      if let selected = selectedAnnotation {
        activeColor = selected.color
        if grabSelected(selected, at: point, handleHitTolerance: handleHitTolerance) {
          return
        }
        statusMessage = selectedStatus(selected)
      }
    } else {
      selectedID = nil
      dragSession = nil
      statusMessage = status(for: .select)
    }
  }

  @discardableResult
  private func grabSelected(
    _ selected: Annotation,
    at point: CGPoint,
    handleHitTolerance: CGFloat,
    allowMove: Bool = true
  ) -> Bool {
    for handle in selected.resizeHandles {
      guard let handlePoint = selected.handlePoint(handle) else { continue }
      let slop = (handle == .arrowCurve || handle == .rectRadius)
        ? handleHitTolerance * 1.35
        : handleHitTolerance
      if hypot(point.x - handlePoint.x, point.y - handlePoint.y) <= slop {
        dragSession = .resize(id: selected.id, handle: handle, original: selected)
        if handle == .arrowCurve {
          statusMessage = "Curve · drag onto the line to straighten"
        } else if handle == .rectRadius {
          statusMessage = "Corner radius · drag onto the corner to square"
        } else {
          statusMessage = "Resizing · ⇧ constrain"
        }
        return true
      }
    }
    if allowMove,
       selected.boundingRect.insetBy(dx: -6, dy: -6).contains(point)
        || selected.hitTest(point, tolerance: 10)
    {
      dragSession = .move(id: selected.id, startPoint: point, original: selected, duplicated: false)
      statusMessage = "Moving · ⌥-drag duplicates"
      return true
    }
    return false
  }

  private func selectedStatus(_ annotation: Annotation) -> String {
    switch annotation.kind {
    case .arrow:
      return "Arrow · drag the middle to curve · L toggles the head"
    case .rectangle:
      return "Rectangle · drag the top-edge dot to round"
    case .spotlight:
      return "Spotlight · drag handles to reshape"
    default:
      return "Selected · arrows nudge · ⌘D duplicate · ⌘[ ⌘] order"
    }
  }

  private func reportDraftSize(start: CGPoint, current: CGPoint) {
    let mods = PointerMods.current
    if tool == .arrow {
      let snapped = snapArrow(from: start, to: current, constrain: mods.shift)
      let len = hypot(snapped.1.x - snapped.0.x, snapped.1.y - snapped.0.y)
      let kind = (mods.option || !arrowHeaded) ? "Line" : "Arrow"
      statusMessage = String(format: "%@ %.0f px", kind, len)
      return
    }
    let rect = shapeRect(from: start, to: current, mods: mods)
    statusMessage = String(format: "%.0f × %.0f", rect.width, rect.height)
  }

  private func reportResizeStatus(_ annotation: Annotation, handle: ResizeHandle) {
    if handle == .rectRadius, case let .rectangle(_, radius) = annotation.kind {
      statusMessage = radius < 1
        ? "Square corners"
        : String(format: "Radius %.0f", radius)
      return
    }
    switch annotation.kind {
    case let .rectangle(rect, _), let .circle(rect), let .highlight(rect), let .spotlight(rect),
         let .redact(rect):
      let r = rect.normalized
      statusMessage = String(format: "%.0f × %.0f", r.width, r.height)
    default:
      break
    }
  }

  private func beginEditText(_ annotation: Annotation) {
    guard case let .text(origin, string) = annotation.kind else { return }
    selectedID = annotation.id
    editingID = annotation.id
    textOrigin = origin
    textDraft = string
    isTyping = true
    draft = .textPlacement(origin)
    dragSession = nil
    didPushForGesture = false
    statusMessage = "Editing text · Esc to finish"
  }

  private func placeBadge(at point: CGPoint) {
    pushHistory()
    let next = annotations.reduce(0) { count, annotation in
      if case .badge = annotation.kind { return count + 1 }
      return count
    } + 1
    annotations.append(Annotation(
      kind: .badge(origin: point, index: next),
      color: activeColor,
      strokeWidth: strokeWidth
    ))
    statusMessage = "Step \(next)"
  }

  private func renumberBadges() {
    var n = 1
    for i in annotations.indices {
      if case let .badge(origin, _) = annotations[i].kind {
        annotations[i].kind = .badge(origin: origin, index: n)
        n += 1
      }
    }
  }

  private func hitTest(_ point: CGPoint) -> UUID? {
    for annotation in annotations.reversed() {
      if annotation.hitTest(point, tolerance: 10) {
        return annotation.id
      }
      switch annotation.kind {
      case .text, .path, .badge, .highlight, .spotlight, .redact:
        if annotation.boundingRect.contains(point) { return annotation.id }
      case .rectangle, .circle:
        if annotation.boundingRect.contains(point) { return annotation.id }
      case .arrow:
        break
      }
    }
    for annotation in annotations.reversed() {
      if annotation.boundingRect.contains(point) {
        return annotation.id
      }
    }
    return nil
  }

  private func commitDraw(at point: CGPoint) {
    let mods = PointerMods.current
    switch draft {
    case let .shape(start, _):
      switch tool {
      case .arrow:
        let snapped = snapArrow(from: start, to: point, constrain: mods.shift)
        if hypot(snapped.1.x - snapped.0.x, snapped.1.y - snapped.0.y) > 4 {
          pushHistory()
          let annotation = Annotation(
            kind: .arrow(
              start: snapped.0,
              end: snapped.1,
              control: nil,
              headed: mods.option ? false : arrowHeaded
            ),
            color: activeColor,
            strokeWidth: strokeWidth
          )
          annotations.append(annotation)
          selectedID = annotation.id
          if case let .arrow(_, _, _, headed) = annotation.kind, !headed {
            statusMessage = "Line · L adds an arrowhead"
          } else {
            statusMessage = "Arrow · drag the middle to curve · L drops the head"
          }
        }
      case .rectangle, .circle, .highlight, .spotlight, .redact:
        let rect = shapeRect(from: start, to: point, mods: mods)
        if rect.width > 2, rect.height > 2 {
          pushHistory()
          let kind: Annotation.Kind
          switch tool {
          case .circle: kind = .circle(rect)
          case .highlight: kind = .highlight(rect)
          case .spotlight: kind = .spotlight(rect)
          case .redact: kind = .redact(rect)
          default: kind = .rectangle(rect, radius: 0)
          }
          let annotation = Annotation(kind: kind, color: activeColor, strokeWidth: strokeWidth)
          annotations.append(annotation)
          if tool == .rectangle {
            selectedID = annotation.id
            statusMessage = "Rectangle · drag the top-edge dot to round"
          } else if tool == .spotlight {
            selectedID = annotation.id
            statusMessage = "Spotlight · drag handles to reshape"
          }
        }
      case .crop:
        commitCrop(shapeRect(from: start, to: point, mods: mods))
      default:
        break
      }
    case var .path(points):
      points.append(point)
      if points.count > 1 {
        pushHistory()
        annotations.append(Annotation(kind: .path(points), color: activeColor, strokeWidth: strokeWidth))
      }
    case .textPlacement, .none:
      break
    }
    draft = nil
  }

  private func commitCrop(_ rect: CGRect) {
    let r = rect.normalized
    guard r.width > 8, r.height > 8 else { return }
    guard let cropped = ImageCropper.crop(image, to: r) else { return }
    pushHistory()
    let delta = CGPoint(x: -r.minX, y: -r.minY)
    annotations = annotations.compactMap { annotation in
      annotation.boundingRect.intersects(r) ? annotation.translated(by: delta) : nil
    }
    image = cropped
    selectedID = nil
    tool = .select
    resetView()
    statusMessage = "Cropped · V select"
  }

  private func replace(id: UUID, with annotation: Annotation) {
    guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
    annotations[index] = annotation
  }

  private func status(for tool: Tool) -> String {
    switch tool {
    case .select:
      return "Select · click · ⌥-click samples · arrows nudge · ⌘D duplicate"
    case .text:
      return "Text · click to place · double-click to edit"
    case .numbered:
      return "Numbers · click to place 1, 2, 3…"
    case .highlight:
      return "Fill · drag a highlight · ⇧ square"
    case .spotlight:
      return "Spotlight · drag a hole · rest of the shot dims"
    case .redact:
      return "Redact · drag to pixelate"
    case .crop:
      return "Crop · drag a region · ⇧ square"
    case .arrow:
      return "Arrow · ⇧ 45° · ⌥ line · drag the middle to curve"
    case .rectangle, .circle:
      return "\(tool.label) · ⇧ constrain · ⌥ from center"
    default:
      return "\(tool.label) · [ ] stroke · S copies & closes"
    }
  }

  private func cleanupTempFile() {
    guard let imageURL,
          imageURL.path.contains("annotator-"),
          imageURL.path.contains(FileManager.default.temporaryDirectory.path)
    else { return }
    try? FileManager.default.removeItem(at: imageURL)
  }
}
