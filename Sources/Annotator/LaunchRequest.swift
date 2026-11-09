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
    // Finder passes -psn_ to CFBundleExecutable. Strip it here so the Swift
    // binary can be that executable. A second Mach-O exec'd by a launcher is
    // not the bundle's signed executable, and macOS 26 MenuBarAgent then
    // refuses the status-item scene.
    let rest = arguments.dropFirst().filter { !$0.hasPrefix("-psn_") }
    if rest.isEmpty || Array(rest) == ["--agent"] {
      return .agent
    }
    if rest.contains("--settings") {
      return .settings
    }
    if rest.contains("--updates") {
      return .updates
    }
    if rest.contains("--activate") {
      return .activate
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

  /// Arguments passed to a newly opened `Annotator.app`, after the executable path.
  var forwardingArguments: [String] {
    switch self {
    case .agent:
      return ["--agent"]
    case .activate:
      return ["--activate"]
    case .settings:
      return ["--settings"]
    case .updates:
      return ["--updates"]
    case .capture(let options):
      var args = ["--capture"]
      if options.window { args.append("--window") }
      if options.fullScreen { args.append("--fullscreen") }
      if options.repeatLast { args.append("--repeat") }
      if options.delay > 0 {
        args.append("--delay")
        args.append(String(options.delay))
      }
      return args
    case .clipboard:
      return ["--clipboard"]
    case .reopen:
      return ["--reopen"]
    case .ocr:
      return ["--ocr"]
    case .image(let path, let wait):
      var args = ["--image", path]
      if wait { args.append("--wait") }
      return args
    case .file(let path):
      return [path]
    }
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
