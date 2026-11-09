import AppKit

extension Notification.Name {
  /// Posted when macOS accepts or rejects the status item after `isVisible = true`.
  static let annotatorMenuBarVisibilityChanged = Notification.Name("annotator.menuBarVisibilityChanged")
}

final class MenuBarController: NSObject, NSMenuDelegate {
  static let shared = MenuBarController()

  var onCapture: ((CaptureAction) -> Void)?
  var onSettings: (() -> Void)?
  var onQuit: (() -> Void)?

  /// True when the status item was created and macOS immediately hid it.
  /// On macOS 26 that is System Settings, Menu Bar, Allow in the Menu Bar.
  private(set) var hiddenBySystem = false

  /// The button has a drawable image or a fallback title. Used by the UI self-test.
  var hasVisibleContent: Bool {
    guard let button = statusItem?.button else { return false }
    if let image = button.image, image.size.width > 1, image.size.height > 1 {
      return true
    }
    return !button.title.isEmpty
  }

  private var statusItem: NSStatusItem?

  func install() {
    if let statusItem {
      reveal(statusItem)
      return
    }
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    // Remember position across launches and let the user Command-drag the icon.
    item.autosaveName = "AnnotatorStatusItem"
    let menu = NSMenu()
    menu.delegate = self
    item.menu = menu
    statusItem = item
    reveal(item)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(shortcutsChanged),
      name: .annotatorShortcutsChanged,
      object: nil
    )
    // The Menu Bar allow list can flip isVisible back to false after we set it.
    DispatchQueue.main.async { [weak self] in
      self?.noteSystemVisibility()
    }
  }

  private func reveal(_ item: NSStatusItem) {
    let image = Self.menuBarImage()
    if let button = item.button {
      button.image = image
      button.image?.isTemplate = true
      button.imagePosition = .imageOnly
      button.toolTip = "Annotator"
      if image == nil {
        button.title = "Annotator"
        button.imagePosition = .imageLeft
        item.length = NSStatusItem.variableLength
      } else {
        button.title = ""
        item.length = NSStatusItem.squareLength
      }
    } else {
      item.length = NSStatusItem.variableLength
      item.button?.title = "Annotator"
    }
    item.isVisible = true
  }

  /// SF Symbol when the system has it, otherwise a drawn template viewfinder.
  /// A nil symbol used to leave a blank status button with nothing to see.
  private static func menuBarImage() -> NSImage? {
    if let symbol = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Annotator") {
      let configured = symbol.withSymbolConfiguration(.init(pointSize: 15, weight: .medium)) ?? symbol
      configured.isTemplate = true
      if configured.size.width > 1, configured.size.height > 1 {
        return configured
      }
    }
    return drawnViewfinder()
  }

  private static func drawnViewfinder() -> NSImage {
    let side: CGFloat = 18
    let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
      NSColor.black.setStroke()
      NSColor.black.setFill()
      let inset = rect.insetBy(dx: 1.6, dy: 1.6)
      let arm: CGFloat = 4.5
      let path = NSBezierPath()
      path.lineWidth = 1.6
      path.lineCapStyle = .square
      func corner(_ x: CGFloat, _ y: CGFloat, _ dx: CGFloat, _ dy: CGFloat) {
        path.move(to: NSPoint(x: x, y: y + dy))
        path.line(to: NSPoint(x: x, y: y))
        path.line(to: NSPoint(x: x + dx, y: y))
      }
      corner(inset.minX, inset.minY, arm, arm)
      corner(inset.maxX, inset.minY, -arm, arm)
      corner(inset.minX, inset.maxY, arm, -arm)
      corner(inset.maxX, inset.maxY, -arm, -arm)
      path.stroke()
      NSBezierPath(
        ovalIn: NSRect(x: rect.midX - 1.4, y: rect.midY - 1.4, width: 2.8, height: 2.8)
      ).fill()
      return true
    }
    image.isTemplate = true
    return image
  }

  /// macOS 26 hides a new status item until the user allows the app. Setting
  /// `isVisible` then reading it back is the only public signal.
  private func noteSystemVisibility() {
    guard let item = statusItem else { return }
    item.isVisible = true
    let blocked = !item.isVisible
    guard blocked != hiddenBySystem else { return }
    hiddenBySystem = blocked
    NotificationCenter.default.post(name: .annotatorMenuBarVisibilityChanged, object: nil)
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    menu.removeAllItems()
    let shortcuts = ShortcutStore.load()
    for action in CaptureAction.allCases {
      let item = NSMenuItem(title: action.title, action: #selector(capture(_:)), keyEquivalent: "")
      item.target = self
      item.tag = Int(action.hotKeyID)
      if let shortcut = shortcuts[action], let equivalent = shortcut.keyEquivalent {
        item.keyEquivalent = equivalent
        item.keyEquivalentModifierMask = shortcut.modifierFlags
      }
      menu.addItem(item)
    }
    menu.addItem(.separator())
    let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings(_:)), keyEquivalent: "")
    settings.target = self
    menu.addItem(settings)
    let updates = NSMenuItem(
      title: "Check for Updates…",
      action: #selector(UpdateController.checkForUpdatesMenu(_:)),
      keyEquivalent: ""
    )
    updates.target = UpdateController.shared
    menu.addItem(updates)
    menu.addItem(.separator())
    let quit = NSMenuItem(title: "Quit Annotator", action: #selector(quit(_:)), keyEquivalent: "q")
    quit.target = self
    menu.addItem(quit)
  }

  @objc private func shortcutsChanged() {
    statusItem?.menu?.update()
  }

  @objc private func capture(_ sender: NSMenuItem) {
    guard let action = CaptureAction.from(hotKeyID: UInt32(sender.tag)) else { return }
    onCapture?(action)
  }

  @objc private func openSettings(_ sender: Any?) {
    onSettings?()
  }

  @objc private func quit(_ sender: Any?) {
    onQuit?()
  }
}
