import AppKit
import CaptureKit
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
    if CommandLine.arguments.contains("--protocol-self-test") {
      exit(AgentBridge.runProtocolSelfTest())
    }
    if CommandLine.arguments.contains("--ui-self-test") {
      exit(runUISelfTest())
    }
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // Accessory avoids Dock/Cmd-Tab and reduces Space-stealing when shown over fullscreen.
    app.setActivationPolicy(.accessory)
    app.run()
  }

  /// Presents the real Settings window and status item. The socket round trip
  /// stays in `--protocol-self-test`, unchanged from the version that passed.
  private static func runUISelfTest() -> Int32 {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let box = UITestBox()
    DispatchQueue.main.async {
      box.code = MainActor.assumeIsolated {
        exercisePackagedUI()
      }
      app.stop(nil)
      if let event = NSEvent.otherEvent(
        with: .applicationDefined,
        location: .zero,
        modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: 0,
        context: nil,
        subtype: 0,
        data1: 0,
        data2: 0
      ) {
        app.postEvent(event, atStart: true)
      }
    }
    app.run()
    return box.code
  }

  @MainActor
  private static func exercisePackagedUI() -> Int32 {
    // Same order as the agent: status item first, then Settings. An exception
    // from setCollectionBehavior fails this test instead of skipping the icon.
    MenuBarController.shared.install()
    let placed = Date().addingTimeInterval(2)
    while Date() < placed && !MenuBarController.shared.hasPlacedButton {
      RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
    }
    if !MenuBarController.shared.hasVisibleContent || !MenuBarController.shared.hasPlacedButton {
      fputs("ui self-test: status item button has no window or a zero frame\n", stderr)
      return 1
    }
    if !SettingsWindow.show() {
      fputs("ui self-test: SettingsWindow.show failed\n", stderr)
      return 1
    }
    if !SettingsWindow.isWindowVisible {
      fputs("ui self-test: settings window is not visible\n", stderr)
      return 1
    }
    return 0
  }
}

private final class UITestBox: @unchecked Sendable {
  var code: Int32 = 1
}

private final class OCRResultBox: @unchecked Sendable {
  var text: String?
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
  private var state: AppState?
  private var panel: AnnotatorWindow?
  private var keyMonitor: Any?
  private var flagMonitor: Any?
  private var keyUpMonitor: Any?

  private var agentMode = false
  private var captureBusy = false
  private var endingEditor = false
  /// Reopen events that arrive as part of this process's own launch are ignored.
  /// A later Finder or `open -a` targets the already-running agent.
  private var acceptReopen = false

  func applicationDidFinishLaunching(_ notification: Notification) {
    installMainMenu()
    installReopenHandler()
    let request = LaunchRequest.parse(CommandLine.arguments)
    switch request {
    case .agent:
      // Finder, Spotlight, and `open -a` pass no capture flags. Login items
      // use the same path, so they start the agent without opening Settings.
      becomeAgentOrExit(presentSettings: !Self.launchedAsLoginItem())
    default:
      if let reply = AgentBridge.send(request) {
        deliverToTerminal(reply, ocr: request.isOCR)
      }
      // Return first so the run loop is spinning before `screencapture -i`.
      DispatchQueue.main.async { [weak self] in
        self?.runOneShot(request)
      }
    }
    DispatchQueue.main.async { [weak self] in
      self?.acceptReopen = true
    }
  }

  /// Finder double-click, Spotlight, and `open -a` while this process is already
  /// running arrive here (or as kAEReopenApplication), not as a new process.
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    guard acceptReopen else { return true }
    presentSettingsFromOpen()
    return true
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // A dismissed NSSavePanel must not quit the editor. The editor closes on
    // Esc, the close button, or Save / S. The menu bar agent keeps running.
    false
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    state?.prepareForTermination()
    AgentBridge.stop()
    return .terminateNow
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    state?.cancelAndQuit()
    return false
  }

  private func showPanel() {
    guard let state else { return }
    let mouse = NSEvent.mouseLocation

    let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
      ?? NSScreen.main
      ?? NSScreen.screens.first
    let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)

    let size = AnnotatorChrome.windowSize(for: state.image.size, visible: visible)

    let panel = AnnotatorWindow(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    panel.title = "Annotator"
    panel.titleVisibility = .hidden
    panel.titlebarAppearsTransparent = false
    panel.titlebarSeparatorStyle = .line
    panel.toolbarStyle = .unified
    panel.tabbingMode = .disallowed
    panel.hidesOnDeactivate = false
    panel.isMovableByWindowBackground = true
    panel.level = .floating
    panel.collectionBehavior = WindowBehavior.allSpaces
    panel.isReleasedWhenClosed = false
    panel.animationBehavior = .none
    panel.minSize = NSSize(width: AnnotatorChrome.minWidth, height: AnnotatorChrome.minHeight)
    panel.delegate = self

    let host = NSHostingController(rootView: RootView(state: state))
    if let hostingView = host.view as? NSHostingView<RootView> {
      hostingView.sizingOptions = []
    }
    panel.contentViewController = host
    panel.toolbar?.allowsUserCustomization = false
    panel.toolbar?.displayMode = .iconOnly

    self.panel = panel

    panel.setContentSize(size)
    let frame = panel.frame
    panel.setFrameOrigin(NSPoint(
      x: visible.midX - frame.width / 2,
      y: visible.midY - frame.height / 2
    ))
    panel.orderFrontRegardless()
    panel.makeKey()
    NSApp.activate(ignoringOtherApps: true)
  }

  private func installEditorHotkeys() {
    removeEditorHotkeys()
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, let state = self.state else { return event }
      return self.handleKey(event, state: state)
    }
    flagMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
      self?.state?.modifiersChanged()
      return event
    }
    keyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
      if event.keyCode == 49 {
        self?.state?.spaceHeld = false
        self?.state?.releaseSpacePalette()
      }
      return event
    }
  }

  private func removeEditorHotkeys() {
    if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    if let flagMonitor { NSEvent.removeMonitor(flagMonitor) }
    if let keyUpMonitor { NSEvent.removeMonitor(keyUpMonitor) }
    keyMonitor = nil
    flagMonitor = nil
    keyUpMonitor = nil
  }

  private func handleKey(_ event: NSEvent, state: AppState) -> NSEvent? {
    if NSApp.modalWindow != nil { return event }
    if let window = event.window, window !== panel { return event }

    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let chars = event.charactersIgnoringModifiers?.lowercased()

    if event.keyCode == 49 {
      if state.isTyping { return event }
      if flags.contains(.command) || flags.contains(.option) || flags.contains(.control) {
        return event
      }
      state.pressSpacePalette()
      return nil
    }

    if state.showToolPalette {
      if event.keyCode == 53 {
        state.hideToolPalette()
        return nil
      }
      if let chars, let char = chars.first, let tool = Tool(hotkey: char) {
        state.pickToolFromPalette(tool)
        return nil
      }
      return nil
    }

    if flags.contains(.command) {
      if chars == "q",
         !flags.contains(.shift), !flags.contains(.option), !flags.contains(.control) {
        NSApp.terminate(nil)
        return nil
      }
      if state.showHelp || state.showToolPalette { return nil }
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

    if state.isTyping, let chars, let char = chars.first, char == "[" || char == "]" {
      state.nudgeStroke(char == "[" ? -1 : 1)
      return nil
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
    case "l":
      state.selectTool(.line)
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
    case "n":
      state.selectTool(.numbered)
      return nil
    case "b":
      state.pressRedact()
      return nil
    case "x":
      state.selectTool(.cross)
      return nil
    case "k":
      state.selectTool(.crop)
      return nil
    case "j":
      state.selectTool(.slice)
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

  private func becomeAgentOrExit(presentSettings: Bool) {
    if let reply = AgentBridge.send(.settings) {
      if !reply.ok, let error = reply.error, !error.isEmpty {
        fputs("Annotator: \(error)\n", stderr)
      }
      exit(reply.code)
    }
    if !AgentBridge.acquireLock() {
      for _ in 0..<20 {
        if let reply = AgentBridge.send(.settings) {
          if !reply.ok, let error = reply.error, !error.isEmpty {
            fputs("Annotator: \(error)\n", stderr)
          }
          exit(reply.code)
        }
        Thread.sleep(forTimeInterval: 0.05)
      }
      fputs("Annotator is already running.\n", stderr)
      exit(0)
    }
    let listening = AgentBridge.start { [weak self] request in
      guard let self else { return .failure("Annotator is not running.") }
      return self.performLocal(request)
    }
    if !listening {
      fputs("Annotator: shortcut handoff is unavailable.\n", stderr)
    }
    startAgent(presentSettings: presentSettings)
  }

  private func startAgent(presentSettings: Bool) {
    agentMode = true
    MenuBarController.shared.onCapture = { action in
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          guard let delegate = NSApp.delegate as? AppDelegate else { return }
          _ = delegate.performLocal(action.request)
        }
      }
    }
    MenuBarController.shared.onSettings = {
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          _ = SettingsWindow.show()
        }
      }
    }
    MenuBarController.shared.onQuit = {
      NSApp.terminate(nil)
    }
    // One status item, before Settings. A second install() calls reveal()
    // again and asks MenuBarAgent for another scene.
    MenuBarController.shared.install()
    HotkeyCenter.shared.onFire = { action in
      DispatchQueue.main.async {
        MainActor.assumeIsolated {
          guard let delegate = NSApp.delegate as? AppDelegate else { return }
          _ = delegate.performLocal(action.request)
        }
      }
    }
    HotkeyCenter.shared.start()
    UpdateController.shared.startAutomaticChecks()
    OCRService.warm()
    if presentSettings || !AgentPreferences.didPresentSettings {
      AgentPreferences.didPresentSettings = true
      SettingsWindow.show()
    }
  }

  private func runOneShot(_ request: LaunchRequest) {
    agentMode = false
    switch request {
    case .ocr:
      deliverToTerminal(performOCR(), ocr: true)
    case .settings:
      startAgent(presentSettings: true)
    case .agent, .activate, .updates:
      startAgent(presentSettings: false)
    default:
      let reply = openEditor(for: request)
      if panel == nil {
        deliverToTerminal(reply, ocr: false)
      }
    }
  }

  private func performLocal(_ request: LaunchRequest) -> AgentReply {
    switch request {
    case .agent, .activate:
      NSApp.activate(ignoringOtherApps: true)
      return .success()
    case .settings:
      MenuBarController.shared.install()
      if SettingsWindow.show() {
        return .success()
      }
      return .failure("Could not open Settings.")
    case .updates:
      UpdateController.shared.checkFromUser()
      return .success()
    case .ocr:
      return performOCR()
    case .capture, .clipboard, .reopen, .image, .file:
      return openEditor(for: request)
    }
  }

  private func openEditor(for request: LaunchRequest) -> AgentReply {
    if captureBusy {
      NSSound.beep()
      return .failure("Annotator is already capturing.")
    }
    if panel != nil {
      if state?.hasMarkup == true {
        focusEditor()
        return .success()
      }
      state?.commitTextIfNeeded(cancel: true)
      state?.flushSession()
      closeEditor()
    }
    captureBusy = true
    let loaded = SessionLoader.load(request)
    captureBusy = false
    switch loaded {
    case .success(let image):
      present(image)
      return .success()
    case .failure(let error):
      if error.silent {
        return .success()
      }
      return .failure(error.message, code: error.code)
    }
  }

  private func present(_ loaded: SessionLoader.LoadedImage) {
    let state = AppState(
      image: loaded.image,
      imageURL: loaded.url,
      cgImage: loaded.cgImage,
      annotations: loaded.annotations,
      remembersSession: loaded.remembersSession
    )
    state.onFinish = { [weak self] in
      self?.closeEditor()
    }
    self.state = state
    installEditorHotkeys()
    showPanel()
  }

  private func closeEditor() {
    if endingEditor { return }
    endingEditor = true
    defer { endingEditor = false }
    removeEditorHotkeys()
    state?.onFinish = nil
    let window = panel
    panel = nil
    state = nil
    window?.delegate = nil
    window?.orderOut(nil)
    window?.contentViewController = nil
    if !agentMode {
      NSApp.terminate(nil)
    }
  }

  private func focusEditor() {
    panel?.orderFrontRegardless()
    panel?.makeKey()
    NSApp.activate(ignoringOtherApps: true)
  }

  private func performOCR() -> AgentReply {
    if captureBusy {
      NSSound.beep()
      return .failure("Annotator is already capturing.")
    }
    captureBusy = true
    defer { captureBusy = false }
    let hidden = panel
    hidden?.orderOut(nil)
    defer {
      if panel === hidden {
        hidden?.orderFrontRegardless()
      }
    }

    OCRService.warm()
    guard let url = CaptureService.capture(locateRegion: false) else {
      return .failure("capture cancelled or failed.")
    }
    defer { try? FileManager.default.removeItem(at: url) }

    let hud = OCRHUDController()
    hud.present()
    hud.flushAppearance()

    let box = OCRResultBox()
    let group = DispatchGroup()
    group.enter()
    DispatchQueue.global(qos: .userInitiated).async {
      box.text = OCRService.recognize(contentsOf: url)
      group.leave()
    }
    while group.wait(timeout: .now() + .milliseconds(16)) == .timedOut {
      RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.016))
    }

    if let text = box.text, !text.isEmpty {
      ClipboardService.copyString(text)
      hud.finishSuccess()
      RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.05))
      hud.dismiss()
      return .success(text: text)
    }

    hud.finishFailure()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 1.05))
    hud.dismiss()
    return AgentReply(ok: false, code: 2, text: "", error: "No text found")
  }

  private func deliverToTerminal(_ reply: AgentReply, ocr: Bool) -> Never {
    if ocr, !reply.text.isEmpty, let data = reply.text.data(using: .utf8) {
      FileHandle.standardOutput.write(data)
    }
    if reply.code != 0, let error = reply.error, !error.isEmpty {
      fputs("Annotator: \(error)\n", stderr)
    }
    exit(reply.code)
  }

  /// `kAEReopenApplication` ('rapp'). LSUIElement apps sometimes get this
  /// Apple event without `applicationShouldHandleReopen`.
  private func installReopenHandler() {
    NSAppleEventManager.shared().setEventHandler(
      self,
      andSelector: #selector(handleReopenEvent(_:withReplyEvent:)),
      forEventClass: AEEventClass(0x61657674),
      andEventID: AEEventID(0x72617070)
    )
  }

  @objc private func handleReopenEvent(
    _ event: NSAppleEventDescriptor,
    withReplyEvent reply: NSAppleEventDescriptor
  ) {
    guard acceptReopen else { return }
    presentSettingsFromOpen()
  }

  private func presentSettingsFromOpen() {
    if agentMode || panel == nil {
      SettingsWindow.show()
    } else {
      focusEditor()
    }
  }

  /// Login items send `keyAELaunchedAsLogInItem` ('lgit') on the open event.
  private static func launchedAsLoginItem() -> Bool {
    guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
    return event.paramDescriptor(forKeyword: AEKeyword(0x6C676974))?.booleanValue == true
  }

  private func installMainMenu() {
    let main = NSMenu()

    let appItem = NSMenuItem()
    main.addItem(appItem)
    let appMenu = NSMenu()
    appItem.submenu = appMenu
    let about = NSMenuItem(title: "About Annotator", action: #selector(showAbout(_:)), keyEquivalent: "")
    about.target = self
    appMenu.addItem(about)
    appMenu.addItem(.separator())
    let settings = NSMenuItem(title: "Settings…", action: #selector(showSettingsAction(_:)), keyEquivalent: "")
    settings.target = self
    appMenu.addItem(settings)
    let updates = NSMenuItem(
      title: "Check for Updates…",
      action: #selector(UpdateController.checkForUpdatesMenu(_:)),
      keyEquivalent: ""
    )
    updates.target = UpdateController.shared
    appMenu.addItem(updates)
    appMenu.addItem(.separator())
    appMenu.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
    let quit = NSMenuItem(title: "Quit Annotator", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appMenu.addItem(quit)

    let editItem = NSMenuItem()
    main.addItem(editItem)
    let edit = NSMenu(title: "Edit")
    editItem.submenu = edit
    edit.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
    let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
    redo.keyEquivalentModifierMask = [.command, .shift]
    edit.addItem(redo)
    edit.addItem(.separator())
    edit.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
    edit.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
    edit.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
    edit.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

    NSApp.mainMenu = main
  }

  @objc private func showAbout(_ sender: Any?) {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(nil)
  }

  @objc private func showSettingsAction(_ sender: Any?) {
    SettingsWindow.show()
  }
}
