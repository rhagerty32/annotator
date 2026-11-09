import Foundation

/// What a process was asked to do. Empty arguments start the menu bar agent.
enum LaunchRequest: Equatable {
  case agent
  case activate
  case settings
  case updates
  case capture(CaptureOptions)
  case clipboard
  case reopen
  case ocr
  case image(path: String, wait: Bool)
  case file(path: String)

  var isOCR: Bool {
    if case .ocr = self { return true }
    return false
  }

  static func parse(_ arguments: [String]) -> LaunchRequest {
    let rest = arguments.dropFirst().filter { !$0.hasPrefix("-psn_") }
    if rest.isEmpty || Array(rest) == ["--agent"] {
      return .agent
    }
    if rest.contains("--settings") {
      return .settings
    }
    if rest.contains("--ocr") {
      return .ocr
    }
    if rest.contains("--clipboard") {
      return .clipboard
    }
    if rest.contains("--reopen") {
      return .reopen
    }
    if rest.contains("--capture") {
      return .capture(CaptureOptions(
        window: rest.contains("--window"),
        fullScreen: rest.contains("--fullscreen"),
        repeatLast: rest.contains("--repeat"),
        delay: delay(in: Array(rest))
      ))
    }
    if let flag = rest.firstIndex(of: "--image") {
      let value = rest.index(after: flag)
      if value < rest.endIndex {
        return .image(path: String(rest[value]), wait: rest.contains("--wait"))
      }
    }
    if let path = rest.first, !path.hasPrefix("-") {
      return .file(path: String(path))
    }
    return .agent
  }

  private static func delay(in args: [String]) -> Int {
    guard let index = args.firstIndex(of: "--delay"), index + 1 < args.count else { return 0 }
    return Int(args[index + 1]) ?? 0
  }
}

struct CaptureOptions: Equatable {
  var window = false
  var fullScreen = false
  var repeatLast = false
  var delay = 0
}

struct SessionError: Error {
  var message: String
  var code: Int32
  /// Cancelled waits exit quietly so Raycast does not treat them as failures.
  var silent = false
}
