import AppKit

final class MenuBarController: NSObject, NSMenuDelegate {
  static let shared = MenuBarController()

  var onCapture: ((CaptureAction) -> Void)?
  var onSettings: (() -> Void)?
  var onQuit: (() -> Void)?

  private var statusItem: NSStatusItem?

  func install() {
    guard statusItem == nil else { return }
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    if let button = item.button {
      let image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Annotator")
      image?.isTemplate = true
      button.image = image
      button.toolTip = "Annotator"
    }
    let menu = NSMenu()
    menu.delegate = self
    item.menu = menu
    statusItem = item
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(shortcutsChanged),
      name: .annotatorShortcutsChanged,
      object: nil
    )
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
