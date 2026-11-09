import Carbon.HIToolbox
import Darwin
import Foundation

/// Global shortcuts via `RegisterEventHotKey`. This API does not need Accessibility.
final class HotkeyCenter {
  static let shared = HotkeyCenter()

  var onFire: ((CaptureAction) -> Void)?

  private var started = false
  private var suspended = false
  private var handlerRef: EventHandlerRef?
  private var hotKeys: [UInt32: EventHotKeyRef] = [:]
  private var shortcuts: [CaptureAction: KeyShortcut] = [:]

  private init() {}

  func start() {
    installHandlerIfNeeded()
    started = true
    _ = reload()
  }

  func suspend() {
    suspended = true
    unregisterAll()
  }

  func resume() {
    suspended = false
    guard started else { return }
    _ = reregister()
  }

  @discardableResult
  func reload() -> String? {
    shortcuts = ShortcutStore.load()
    guard started, !suspended else { return nil }
    return reregister()
  }

  func handle(id: UInt32) {
    guard let action = CaptureAction.from(hotKeyID: id) else { return }
    onFire?(action)
  }

  private func installHandlerIfNeeded() {
    guard handlerRef == nil else { return }
    var spec = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )
    let status = InstallEventHandler(
      GetApplicationEventTarget(),
      hotKeyCallback,
      1,
      &spec,
      Unmanaged.passUnretained(self).toOpaque(),
      &handlerRef
    )
    if status != noErr {
      fputs("Annotator: could not install the shortcut handler (\(status))\n", stderr)
    }
  }

  private func reregister() -> String? {
    unregisterAll()
    var problem: String?
    for action in CaptureAction.allCases {
      guard let shortcut = shortcuts[action] else { continue }
      switch register(shortcut, id: action.hotKeyID) {
      case .success:
        break
      case .conflict:
        problem = "\(action.title) is already in use. Pick another shortcut."
      case .failed:
        problem = "\(action.title) could not be registered."
      }
    }
    return problem
  }

  private enum RegisterResult {
    case success
    case conflict
    case failed
  }

  private func register(_ shortcut: KeyShortcut, id: UInt32) -> RegisterResult {
    var ref: EventHotKeyRef?
    let hotKeyID = EventHotKeyID(signature: OSType(0x414E4F54), id: id)
    let status = RegisterEventHotKey(
      shortcut.keyCode,
      shortcut.modifiers,
      hotKeyID,
      GetApplicationEventTarget(),
      0,
      &ref
    )
    if status == noErr, let ref {
      hotKeys[id] = ref
      return .success
    }
    // Carbon eventHotKeyExistsErr. Another app, or macOS, already owns this chord.
    if status == OSStatus(-9878) {
      return .conflict
    }
    return .failed
  }

  private func unregisterAll() {
    for ref in hotKeys.values {
      UnregisterEventHotKey(ref)
    }
    hotKeys.removeAll()
  }
}

private func readHotKeyID(_ event: EventRef) -> EventHotKeyID? {
  var hotKeyID = EventHotKeyID()
  let status = withUnsafeMutableBytes(of: &hotKeyID) { buffer in
    GetEventParameter(
      event,
      EventParamName(kEventParamDirectObject),
      EventParamType(typeEventHotKeyID),
      nil,
      numericCast(buffer.count),
      nil,
      buffer.baseAddress
    )
  }
  return status == noErr ? hotKeyID : nil
}

/// No nested closures here: this value has to be a C function pointer.
private let hotKeyCallback: EventHandlerUPP = { _, event, userData in
  guard let event, let userData, let hotKeyID = readHotKeyID(event) else {
    return OSStatus(-9874)
  }
  let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
  center.handle(id: hotKeyID.id)
  return noErr
}
