import AppKit
import SwiftUI

/// Plain window so AppKit will not auto-dismiss on Escape / save-panel Cancel
/// the way `NSPanel` does (`cancelOperation` → `close`).
final class AnnotatorWindow: NSWindow {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }

  override func cancelOperation(_ sender: Any?) {
    // Escape is handled in AppDelegate. Do not close the editor.
  }
}

@main
enum AnnotatorMain {
  static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // Accessory avoids Dock/Cmd-Tab and reduces Space-stealing when shown over fullscreen.
    app.setActivationPolicy(.accessory)
    app.run()
  }
}

private final class OCRResultBox: @unchecked Sendable {
  var text: String?
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  private var state: AppState!
  private var panel: AnnotatorWindow?
  private var keyMonitor: Any?
  private var flagMonitor: Any?
  private var keyUpMonitor: Any?

  func applicationDidFinishLaunching(_ notification: Notification) {
    if CommandLine.arguments.contains("--ocr") {
      Self.runOCRAndExit()
    }

    // Return first so the run loop is spinning before `screencapture -i`
    // (needed for last-region mouse tracking, and so the picker can appear).
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      let loaded = Self.loadLaunchImage()
      self.state = AppState(image: loaded.image, imageURL: loaded.url)
      self.installHotkeys()
      self.showPanel()
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // A dismissed NSSavePanel must not quit the editor. Quit only via Esc, the
    // close button, or Save / S (see windowShouldClose, cancelAndQuit, saveAndQuit).
    false
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    state.cancelAndQuit()
    return false
  }

  private static func runOCRAndExit() -> Never {
    OCRService.warm()

    guard let url = CaptureService.capture(locateRegion: false) else {
      exit(1)
    }

    func cleanup() {
      try? FileManager.default.removeItem(at: url)
    }

    let hud = OCRHUDController()
    hud.present()
    hud.flushAppearance()

    guard let image = NSImage(contentsOf: url) else {
      hud.finishFailure()
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.05))
      hud.dismiss()
      cleanup()
      exit(1)
    }

    let box = OCRResultBox()
    let group = DispatchGroup()
    group.enter()
    DispatchQueue.global(qos: .userInitiated).async {
      box.text = OCRService.recognize(image)
      group.leave()
    }

    while group.wait(timeout: .now() + .milliseconds(16)) == .timedOut {
      RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.016))
    }

    if let text = box.text, !text.isEmpty {
      if let data = text.data(using: .utf8) {
        FileHandle.standardOutput.write(data)
      }
      hud.finishSuccess()
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.05))
      hud.dismiss()
      cleanup()
      exit(0)
    }

    hud.finishFailure()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.05))
    hud.dismiss()
    cleanup()
    exit(2)
  }

  private func showPanel() {
    let mouse = NSEvent.mouseLocation

    let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
      ?? NSScreen.main
      ?? NSScreen.screens.first
    let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
    let bounds = screen?.frame ?? visible

    let size = AnnotatorChrome.windowSize(for: state.image.size, visible: visible)

    let frame = NSRect(
      x: bounds.midX - size.width / 2,
      y: bounds.midY - size.height / 2,
      width: size.width,
      height: size.height
    )

    let panel = AnnotatorWindow(
      contentRect: frame,
      styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    panel.title = "Annotator"
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = true
    panel.hidesOnDeactivate = false
    panel.isMovableByWindowBackground = true
    panel.level = .floating
    panel.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]
    panel.isReleasedWhenClosed = false
    panel.animationBehavior = .none
    panel.minSize = NSSize(width: AnnotatorChrome.minWidth, height: AnnotatorChrome.minHeight)
    panel.delegate = self

    let root = RootView(state: state)
    panel.contentView = NSHostingView(rootView: root)

    self.panel = panel

    panel.setFrame(frame, display: true)
    panel.orderFrontRegardless()
    panel.makeKey()
    NSApp.activate(ignoringOtherApps: true)
  }

  private func installHotkeys() {
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, let state = self.state else { return event }
      return self.handleKey(event, state: state)
    }
    flagMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
      self?.state.modifiersChanged()
      return event
    }
    keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
      if event.keyCode == 49 {
        self?.state.spaceHeld = false
      }
      return event
    }
  }

  private func handleKey(_ event: NSEvent, state: AppState) -> NSEvent? {
    if NSApp.modalWindow != nil { return event }
    if let window = event.window, window !== panel { return event }

    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let chars = event.charactersIgnoringModifiers?.lowercased()

    if flags.contains(.command) {
      if state.showHelp { return nil }
      if state.isTyping { return event }
      switch chars {
      case "z":
        if flags.contains(.shift) {
          state.redo()
        } else {
          state.undo()
        }
        return nil
      case "c":
        state.copyToClipboard()
        return nil
      case "s":
        state.saveToDisk()
        return nil
      case "=", "+":
        state.nudgeZoom(factor: 1.25)
        return nil
      case "-", "_":
        state.nudgeZoom(factor: 0.8)
        return nil
      case "0":
        state.resetView()
        return nil
      case "d":
        state.duplicateSelection()
        return nil
      case "[":
        state.sendBackward()
        return nil
      case "]":
        state.bringForward()
        return nil
      case ",":
        state.toggleSettings()
        return nil
      default:
        return event
      }
    }

    if Self.isHelpKey(event), !state.isTyping {
      state.toggleHelp()
      return nil
    }

    if state.showHelp {
      if event.keyCode == 53 {
        _ = state.handleEscape()
        return nil
      }
      return nil
    }

    if event.keyCode == 49, !state.isTyping {
      state.spaceHeld = true
      return nil
    }

    if flags.contains(.option) || flags.contains(.control) {
      return event
    }

    if !state.isTyping,
       let chars,
       let char = chars.first,
       let color = AnnotationColor.allCases.first(where: { $0.digitHotkey == String(char) })
    {
      state.setColor(color)
      return nil
    }

    if event.keyCode == 53 { // Escape
      if state.handleEscape() {
        return nil
      }
      state.cancelAndQuit()
      return nil
    }

    if event.keyCode == 36 { // Return
      if !state.isTyping, case .text = state.selectedAnnotation?.kind {
        state.editSelectedText()
        return nil
      }
      return event
    }

    if event.keyCode == 51 || event.keyCode == 117 {
      if !state.isTyping, state.selectedID != nil {
        state.deleteSelection()
        return nil
      }
      return event
    }

    if !state.isTyping, state.selectedID != nil {
      let step: CGFloat = flags.contains(.shift) ? 10 : 1
      switch event.keyCode {
      case 123:
        state.nudgeSelection(dx: -step, dy: 0)
        return nil
      case 124:
        state.nudgeSelection(dx: step, dy: 0)
        return nil
      case 125:
        state.nudgeSelection(dx: 0, dy: step)
        return nil
      case 126:
        state.nudgeSelection(dx: 0, dy: -step)
        return nil
      default:
        break
      }
    }

    guard !state.isTyping else {
      return event
    }

    guard let chars, let char = chars.first else {
      return event
    }

    switch char {
    case "v":
      state.selectTool(.select)
      return nil
    case "r":
      state.selectTool(.rectangle)
      return nil
    case "c":
      state.selectTool(.circle)
      return nil
    case "a":
      state.selectTool(.arrow)
      return nil
    case "d":
      state.selectTool(.draw)
      return nil
    case "t":
      state.selectTool(.text)
      return nil
    case "h":
      state.selectTool(.highlight)
      return nil
    case "i":
      state.selectTool(.spotlight)
      return nil
    case "l":
      state.toggleArrowHead()
      return nil
    case "n":
      state.selectTool(.numbered)
      return nil
    case "b":
      state.selectTool(.redact)
      return nil
    case "x":
      state.selectTool(.crop)
      return nil
    case "[":
      state.nudgeStroke(-1)
      return nil
    case "]":
      state.nudgeStroke(1)
      return nil
    case "s":
      if flags.contains(.shift) {
        state.saveToDisk()
      } else {
        state.saveAndQuit()
      }
      return nil
    default:
      return event
    }
  }

  private static func isHelpKey(_ event: NSEvent) -> Bool {
    if event.characters == "?" { return true }
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    return event.charactersIgnoringModifiers == "/" && flags.contains(.shift)
  }

  private struct LoadedImage {
    let image: NSImage
    let url: URL?
  }

  private static func loadLaunchImage() -> LoadedImage {
    let args = CommandLine.arguments
    let delay: Int = {
      guard let index = args.firstIndex(of: "--delay"),
            args.index(after: index) < args.endIndex
      else { return 0 }
      return Int(args[args.index(after: index)]) ?? 0
    }()

    if args.contains("--clipboard") {
      if let image = ClipboardService.imageFromPasteboard() {
        return LoadedImage(image: image, url: nil)
      }
      fputs("Annotator: no image on the clipboard.\n", stderr)
      exit(1)
    }

    if args.contains("--capture") {
      if let url = CaptureService.capture(
        window: args.contains("--window"),
        delaySeconds: delay,
        fullScreen: args.contains("--fullscreen"),
        repeatLast: args.contains("--repeat")
      ),
         let image = NSImage(contentsOf: url)
      {
        return LoadedImage(image: image, url: url)
      }
      fputs("Annotator: capture cancelled or failed.\n", stderr)
      exit(1)
    }

    if let pathIndex = args.firstIndex(of: "--image"),
       args.index(after: pathIndex) < args.endIndex
    {
      let path = args[args.index(after: pathIndex)]
      let url = URL(fileURLWithPath: path)
      if let image = NSImage(contentsOf: url) {
        return LoadedImage(image: image, url: url)
      }
      fputs("Annotator: could not load image at \(path)\n", stderr)
      exit(1)
    }

    if args.count > 1 {
      let path = args[1]
      if !path.hasPrefix("-"), let image = NSImage(contentsOfFile: path) {
        return LoadedImage(image: image, url: URL(fileURLWithPath: path))
      }
    }

    let size = NSSize(width: 1280, height: 800)
    let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: Int(size.width),
      pixelsHigh: Int(size.height),
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    )!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
      NSGraphicsContext.current = ctx
      NSColor.windowBackgroundColor.setFill()
      NSRect(origin: .zero, size: size).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    let fallback = NSImage(size: size)
    fallback.addRepresentation(rep)
    return LoadedImage(image: fallback, url: nil)
  }
}
