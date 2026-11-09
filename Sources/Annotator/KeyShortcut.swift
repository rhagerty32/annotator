import AppKit
import CaptureKit
import Carbon.HIToolbox
import Foundation

/// Carbon modifier bits passed to `RegisterEventHotKey`. Order on screen is ⌃⌥⇧⌘.
enum CarbonModifier {
  static let command = UInt32(cmdKey)
  static let shift = UInt32(shiftKey)
  static let option = UInt32(optionKey)
  static let control = UInt32(controlKey)
  static let chord = command | option | control
}

struct KeyShortcut: Codable, Equatable {
  var keyCode: UInt32
  var modifiers: UInt32
  var displayKey: String

  static let captureRegion = KeyShortcut(
    keyCode: UInt32(kVK_ANSI_A),
    modifiers: CarbonModifier.control | CarbonModifier.option,
    displayKey: "A"
  )

  var hasChordModifier: Bool {
    modifiers & CarbonModifier.chord != 0
  }

  /// ⇧⌘3, ⇧⌘4, and ⇧⌘5 are the system screenshot shortcuts.
  var blocksSystemScreenshot: Bool {
    let shot = CarbonModifier.command | CarbonModifier.shift
    guard modifiers == shot else { return false }
    if [UInt32(kVK_ANSI_3), UInt32(kVK_ANSI_4), UInt32(kVK_ANSI_5)].contains(keyCode) {
      return true
    }
    return ["3", "4", "5"].contains(displayKey)
  }

  func sameChord(as other: KeyShortcut) -> Bool {
    keyCode == other.keyCode && modifiers == other.modifiers
  }

  var displayString: String {
    var text = ""
    if modifiers & CarbonModifier.control != 0 { text += "⌃" }
    if modifiers & CarbonModifier.option != 0 { text += "⌥" }
    if modifiers & CarbonModifier.shift != 0 { text += "⇧" }
    if modifiers & CarbonModifier.command != 0 { text += "⌘" }
    text += displayKey
    return text
  }

  var keyEquivalent: String? {
    guard displayKey.count == 1, let scalar = displayKey.unicodeScalars.first, scalar.isASCII else {
      return nil
    }
    return displayKey.lowercased()
  }

  var modifierFlags: NSEvent.ModifierFlags {
    var flags: NSEvent.ModifierFlags = []
    if modifiers & CarbonModifier.control != 0 { flags.insert(.control) }
    if modifiers & CarbonModifier.option != 0 { flags.insert(.option) }
    if modifiers & CarbonModifier.shift != 0 { flags.insert(.shift) }
    if modifiers & CarbonModifier.command != 0 { flags.insert(.command) }
    return flags
  }

  static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
    var mods: UInt32 = 0
    if flags.contains(.command) { mods |= CarbonModifier.command }
    if flags.contains(.shift) { mods |= CarbonModifier.shift }
    if flags.contains(.option) { mods |= CarbonModifier.option }
    if flags.contains(.control) { mods |= CarbonModifier.control }
    return mods
  }

  static func displayKey(for event: NSEvent) -> String {
    switch Int(event.keyCode) {
    case 49: return "Space"
    case 36: return "Return"
    case 48: return "Tab"
    case 51: return "Delete"
    case 53: return "Escape"
    case 123: return "Left"
    case 124: return "Right"
    case 125: return "Down"
    case 126: return "Up"
    case 122: return "F1"
    case 120: return "F2"
    case 99: return "F3"
    case 118: return "F4"
    case 96: return "F5"
    case 97: return "F6"
    case 98: return "F7"
    case 100: return "F8"
    case 101: return "F9"
    case 109: return "F10"
    case 103: return "F11"
    case 111: return "F12"
    default:
      break
    }
    if let raw = event.charactersIgnoringModifiers, raw.count == 1, let character = raw.first, !character.isWhitespace {
      return String(character).uppercased()
    }
    return "Key \(event.keyCode)"
  }
}

enum CaptureAction: String, CaseIterable, Identifiable {
  case region
  case window
  case fullScreen
  case lastRegion
  case copyText
  case reopen

  var id: String { rawValue }

  var title: String {
    switch self {
    case .region: return "Capture Region"
    case .window: return "Capture Window"
    case .fullScreen: return "Capture Full Screen"
    case .lastRegion: return "Capture Last Region"
    case .copyText: return "Copy Text from Screen"
    case .reopen: return "Reopen Last Shot"
    }
  }

  var hotKeyID: UInt32 {
    switch self {
    case .region: return 1
    case .window: return 2
    case .fullScreen: return 3
    case .lastRegion: return 4
    case .copyText: return 5
    case .reopen: return 6
    }
  }

  var request: LaunchRequest {
    switch self {
    case .region:
      return .capture(CaptureOptions())
    case .window:
      return .capture(CaptureOptions(window: true))
    case .fullScreen:
      return .capture(CaptureOptions(fullScreen: true))
    case .lastRegion:
      return .capture(CaptureOptions(repeatLast: true))
    case .copyText:
      return .ocr
    case .reopen:
      return .reopen
    }
  }

  static func from(hotKeyID: UInt32) -> CaptureAction? {
    allCases.first { $0.hotKeyID == hotKeyID }
  }
}

extension Notification.Name {
  static let annotatorShortcutsChanged = Notification.Name("annotator.shortcutsChanged")
}

enum ShortcutStore {
  static var fileURL: URL {
    AnnotatorFiles.supportDirectory.appendingPathComponent("shortcuts.json")
  }

  static func load() -> [CaptureAction: KeyShortcut] {
    guard let data = try? Data(contentsOf: fileURL),
          let raw = try? JSONDecoder().decode([String: KeyShortcut].self, from: data)
    else {
      return [.region: .captureRegion]
    }
    var result: [CaptureAction: KeyShortcut] = [:]
    for action in CaptureAction.allCases {
      if let shortcut = raw[action.rawValue] {
        result[action] = shortcut
      }
    }
    return result
  }

  static func save(_ shortcuts: [CaptureAction: KeyShortcut]) {
    var raw: [String: KeyShortcut] = [:]
    for (action, shortcut) in shortcuts {
      raw[action.rawValue] = shortcut
    }
    guard let data = try? JSONEncoder().encode(raw) else { return }
    try? data.write(to: fileURL, options: .atomic)
  }
}

enum AgentPreferences {
  private static var marker: URL {
    AnnotatorFiles.supportDirectory.appendingPathComponent("did-present-settings")
  }

  static var didPresentSettings: Bool {
    get { FileManager.default.fileExists(atPath: marker.path) }
    set {
      if newValue {
        FileManager.default.createFile(atPath: marker.path, contents: Data())
      } else {
        try? FileManager.default.removeItem(at: marker)
      }
    }
  }
}
