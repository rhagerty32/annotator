import AppKit
import SwiftUI

@MainActor
final class SettingsModel: ObservableObject {
  @Published var shortcuts: [CaptureAction: KeyShortcut]
  @Published var launchAtLogin: Bool
  @Published var loginDetail: String
  @Published var shortcutMessage: String?
  @Published var shortcutMessageIsError = false
  @Published var recording: CaptureAction?
  @Published var menuBarHiddenBySystem = false

  init() {
    shortcuts = ShortcutStore.load()
    launchAtLogin = LoginItem.isEnabled
    loginDetail = LoginItem.detail
    menuBarHiddenBySystem = MenuBarController.shared.hiddenBySystem
  }

  func refreshMenuBar() {
    menuBarHiddenBySystem = MenuBarController.shared.hiddenBySystem
  }

  var menuBarNote: String {
    if menuBarHiddenBySystem {
      return "macOS is hiding the menu bar icon. Open System Settings, choose Menu Bar, and turn Annotator on under Allow in the Menu Bar."
    }
    return "If the viewfinder is missing, open System Settings, choose Menu Bar, and turn Annotator on under Allow in the Menu Bar. A full or notched menu bar can hide it too. Open Annotator again to bring this window back."
  }

  func refreshLogin() {
    launchAtLogin = LoginItem.isEnabled
    loginDetail = LoginItem.detail
  }

  func setLaunchAtLogin(_ enabled: Bool) {
    guard LoginItem.isBundledApp else {
      launchAtLogin = false
      loginDetail = LoginItem.detail
      return
    }
    do {
      try LoginItem.setEnabled(enabled)
    } catch {
      loginDetail = error.localizedDescription
      launchAtLogin = LoginItem.isEnabled
      return
    }
    refreshLogin()
  }

  func beginRecording(_ action: CaptureAction) {
    recording = action
    shortcutMessage = nil
  }

  func cancelRecording() {
    recording = nil
  }

  func reject(_ message: String) {
    shortcutMessage = message
    shortcutMessageIsError = true
  }

  func setShortcut(_ shortcut: KeyShortcut?, for action: CaptureAction) {
    recording = nil
    if let shortcut {
      if !shortcut.hasChordModifier {
        reject("Add Control, Option, or Command.")
        return
      }
      if shortcut.blocksSystemScreenshot {
        reject("Shift Command 3, 4, and 5 belong to macOS screenshots.")
        return
      }
    }

    var next = shortcuts
    var movedFrom: String?
    if let shortcut {
      for other in CaptureAction.allCases where other != action && next[other]?.sameChord(as: shortcut) == true {
        next[other] = nil
        movedFrom = other.title
      }
      next[action] = shortcut
    } else {
      next[action] = nil
    }
    shortcuts = next
    ShortcutStore.save(next)
    NotificationCenter.default.post(name: .annotatorShortcutsChanged, object: nil)
    if let problem = HotkeyCenter.shared.reload() {
      reject(problem)
      return
    }
    if let movedFrom {
      shortcutMessage = "That shortcut moved from \(movedFrom)."
      shortcutMessageIsError = false
    } else if shortcut == nil {
      shortcutMessage = "Shortcut cleared."
      shortcutMessageIsError = false
    } else {
      shortcutMessage = nil
    }
  }
}

struct SettingsView: View {
  @ObservedObject var model: SettingsModel

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      section("Shortcuts") {
        VStack(alignment: .leading, spacing: 2) {
          ForEach(CaptureAction.allCases) { action in
            shortcutRow(action)
          }
        }
        caption(
          model.shortcutMessage ?? "Click a shortcut, then press the keys. Delete clears it.",
          isError: model.shortcutMessageIsError && model.shortcutMessage != nil
        )
      }

      Divider().padding(.vertical, 14)

      section("General") {
        Toggle("Launch at Login", isOn: Binding(
          get: { model.launchAtLogin },
          set: { model.setLaunchAtLogin($0) }
        ))
        .disabled(!LoginItem.isBundledApp)
        .toggleStyle(.switch)
        caption(model.loginDetail, isError: false)
        caption(model.menuBarNote, isError: model.menuBarHiddenBySystem)
      }

      Divider().padding(.vertical, 14)

      section("Updates") {
        HStack {
          Text("Version")
          Spacer(minLength: 12)
          Text(UpdateController.versionLabel)
            .foregroundStyle(.secondary)
        }
        .font(.system(size: 13))
        Button("Check for Updates…") {
          UpdateController.shared.checkFromUser()
        }
        caption(UpdateController.statusDetail, isError: false)
      }
    }
    .padding(20)
    .frame(width: 440)
    .fixedSize(horizontal: true, vertical: true)
    .background(Color(nsColor: .windowBackgroundColor))
    .onAppear {
      model.refreshLogin()
      model.refreshMenuBar()
    }
    .onReceive(NotificationCenter.default.publisher(for: .annotatorMenuBarVisibilityChanged)) { _ in
      model.refreshMenuBar()
    }
    .onDisappear {
      model.cancelRecording()
      HotkeyCenter.shared.resume()
    }
    .onChange(of: model.recording) { _, action in
      if action == nil {
        HotkeyCenter.shared.resume()
      } else {
        HotkeyCenter.shared.suspend()
      }
    }
  }

  private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
        .tracking(0.5)
      content()
    }
  }

  private func shortcutRow(_ action: CaptureAction) -> some View {
    HStack(spacing: 12) {
      Text(action.title)
        .font(.system(size: 13))
      Spacer(minLength: 8)
      ShortcutRecorder(
        shortcut: model.shortcuts[action],
        isRecording: model.recording == action,
        onBegin: { model.beginRecording(action) },
        onCancel: { model.cancelRecording() },
        onFinish: { model.setShortcut($0, for: action) },
        onReject: { model.reject($0) }
      )
      .frame(width: 132, height: 24)
    }
    .padding(.vertical, 3)
  }

  private func caption(_ text: String, isError: Bool) -> some View {
    Text(text)
      .font(.system(size: 11))
      .foregroundStyle(isError ? Color.red : Color.secondary)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.top, 2)
  }
}

struct ShortcutRecorder: NSViewRepresentable {
  var shortcut: KeyShortcut?
  var isRecording: Bool
  var onBegin: () -> Void
  var onCancel: () -> Void
  var onFinish: (KeyShortcut?) -> Void
  var onReject: (String) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  func makeNSView(context: Context) -> RecorderView {
    let view = RecorderView()
    view.coordinator = context.coordinator
    return view
  }

  func updateNSView(_ view: RecorderView, context: Context) {
    context.coordinator.parent = self
    view.shortcut = shortcut
    view.isRecording = isRecording
    view.needsDisplay = true
    if isRecording, view.window?.firstResponder !== view {
      view.window?.makeFirstResponder(view)
    }
  }

  final class Coordinator {
    var parent: ShortcutRecorder
    init(_ parent: ShortcutRecorder) {
      self.parent = parent
    }
  }
}

final class RecorderView: NSView {
  weak var coordinator: ShortcutRecorder.Coordinator?
  var shortcut: KeyShortcut?
  var isRecording = false {
    didSet {
      if !isRecording { liveModifiers = "" }
      needsDisplay = true
    }
  }
  private var liveModifiers = ""

  override var acceptsFirstResponder: Bool { true }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: .pointingHand)
  }

  override func draw(_ dirtyRect: NSRect) {
    let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
    let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
    let fill = isRecording
      ? NSColor.controlAccentColor.withAlphaComponent(0.14)
      : NSColor.controlBackgroundColor
    fill.setFill()
    path.fill()
    let stroke = isRecording ? NSColor.controlAccentColor : NSColor.separatorColor
    stroke.setStroke()
    path.lineWidth = isRecording ? 1.5 : 1
    path.stroke()

    let title = label
    let placeholder = !isRecording && shortcut == nil
    let attrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 13, weight: .medium),
      .foregroundColor: placeholder || (isRecording && shortcut == nil && liveModifiers.isEmpty)
        ? NSColor.secondaryLabelColor
        : NSColor.labelColor,
    ]
    let size = title.size(withAttributes: attrs)
    title.draw(at: NSPoint(
      x: (bounds.width - size.width) / 2,
      y: (bounds.height - size.height) / 2 - 0.5
    ), withAttributes: attrs)
  }

  override func mouseDown(with event: NSEvent) {
    window?.makeFirstResponder(self)
    coordinator?.parent.onBegin()
  }

  override func keyDown(with event: NSEvent) {
    guard isRecording else { return }
    handle(event)
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard isRecording else { return super.performKeyEquivalent(with: event) }
    handle(event)
    return true
  }

  override func flagsChanged(with event: NSEvent) {
    guard isRecording else { return }
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    liveModifiers = KeyShortcut(
      keyCode: 0,
      modifiers: KeyShortcut.carbonModifiers(from: flags),
      displayKey: ""
    ).displayString
    needsDisplay = true
  }

  override func resignFirstResponder() -> Bool {
    if isRecording {
      coordinator?.parent.onCancel()
    }
    return super.resignFirstResponder()
  }

  private var label: String {
    if isRecording {
      if liveModifiers.isEmpty { return "Type Shortcut" }
      return liveModifiers
    }
    return shortcut?.displayString ?? "None"
  }

  private func handle(_ event: NSEvent) {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let bare = flags.intersection([.command, .option, .control, .shift]).isEmpty
    if event.keyCode == 53 && bare {
      coordinator?.parent.onCancel()
      return
    }
    if (event.keyCode == 51 || event.keyCode == 117) && bare {
      coordinator?.parent.onFinish(nil)
      return
    }
    let shortcut = KeyShortcut(
      keyCode: UInt32(event.keyCode),
      modifiers: KeyShortcut.carbonModifiers(from: flags),
      displayKey: KeyShortcut.displayKey(for: event)
    )
    if !shortcut.hasChordModifier {
      NSSound.beep()
      coordinator?.parent.onReject("Add Control, Option, or Command.")
      return
    }
    if shortcut.blocksSystemScreenshot {
      NSSound.beep()
      coordinator?.parent.onReject("Shift Command 3, 4, and 5 belong to macOS screenshots.")
      return
    }
    coordinator?.parent.onFinish(shortcut)
  }
}

@MainActor
enum SettingsWindow {
  private static var controller: Controller?

  static func show() {
    if controller == nil {
      controller = Controller()
    }
    controller?.show()
  }

  final class Controller: NSWindowController, NSWindowDelegate {
    let model: SettingsModel

    init() {
      let model = SettingsModel()
      self.model = model
      let host = NSHostingController(rootView: SettingsView(model: model))
      let window = NSWindow(contentViewController: host)
      window.title = "Settings"
      window.styleMask = [.titled, .closable, .miniaturizable]
      window.isReleasedWhenClosed = false
      window.level = .floating
      window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
      window.titlebarAppearsTransparent = false
      super.init(window: window)
      window.delegate = self
      host.view.layoutSubtreeIfNeeded()
      let fitted = host.view.fittingSize
      let height = fitted.height > 200 && fitted.height < 900 ? fitted.height : 560
      window.setContentSize(NSSize(width: 440, height: height))
      window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    func show() {
      model.refreshLogin()
      guard let window else { return }
      // Stay an accessory app. Switching back to .accessory after ordering the
      // window front was hiding Settings again on the next turn.
      window.level = .floating
      window.hidesOnDeactivate = false
      window.collectionBehavior.formUnion([.canJoinAllSpaces, .fullScreenAuxiliary, .moveToActiveSpace])
      if window.isMiniaturized {
        window.deminiaturize(nil)
      }
      NSApp.activate(ignoringOtherApps: true)
      window.makeKeyAndOrderFront(nil)
      window.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
      model.cancelRecording()
      HotkeyCenter.shared.resume()
    }
  }
}
