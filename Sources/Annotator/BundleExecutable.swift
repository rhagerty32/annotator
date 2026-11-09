import Darwin
import Foundation

/// The menu bar agent has to be the app's `CFBundleExecutable`.
///
/// `AnnotatorBin` sits in the same bundle, and a SwiftPM binary has no bundle.
/// MenuBarAgent on macOS 26 rejects a status-item scene when the running image
/// is not the executable named by Info.plist.
enum BundleExecutable {
  static var currentURL: URL {
    let path = executablePath() ?? CommandLine.arguments.first ?? ""
    return URL(fileURLWithPath: path).standardizedFileURL
  }

  private static func executablePath() -> String? {
    var size: UInt32 = 4096
    var buffer = [CChar](repeating: 0, count: Int(size))
    let status = buffer.withUnsafeMutableBufferPointer { pointer -> Int32 in
      guard let base = pointer.baseAddress else { return -1 }
      return _NSGetExecutablePath(base, &size)
    }
    if status == -1, size > 0 {
      buffer = [CChar](repeating: 0, count: Int(size))
      let again = buffer.withUnsafeMutableBufferPointer { pointer -> Int32 in
        guard let base = pointer.baseAddress else { return -1 }
        return _NSGetExecutablePath(base, &size)
      }
      guard again == 0 else { return nil }
    } else if status != 0 {
      return nil
    }
    return buffer.withUnsafeBufferPointer { pointer in
      guard let base = pointer.baseAddress else { return nil }
      return String(cString: base)
    }
  }

  /// Resolved path of this process.
  static var currentPath: String {
    resolved(currentURL).path
  }

  /// `Bundle.main.executableURL` follows the running image. Inside an app,
  /// running `AnnotatorBin` makes that URL `AnnotatorBin`, not the
  /// `CFBundleExecutable` named in Info.plist. The agent check uses the plist.
  static var mainExecutablePath: String {
    guard let url = Bundle.main.executableURL else { return "none" }
    return resolved(url).path
  }

  /// `Contents/MacOS/<CFBundleExecutable>`, or nil outside an application bundle.
  static var bundleExecutableURL: URL? {
    guard Bundle.main.bundleURL.pathExtension == "app",
          let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String,
          !name.isEmpty
    else {
      return nil
    }
    return Bundle.main.bundleURL
      .appendingPathComponent("Contents/MacOS", isDirectory: true)
      .appendingPathComponent(name)
  }

  static var bundleExecutablePath: String {
    guard let bundleExecutableURL else { return "none" }
    return resolved(bundleExecutableURL).path
  }

  /// True only for the Mach-O named by `CFBundleExecutable`.
  static var isBundleExecutable: Bool {
    guard let expected = bundleExecutableURL else { return false }
    return resolved(currentURL).path == resolved(expected).path
  }

  /// App to open when this process must not stay up as the agent.
  /// Inside `Annotator.app` that is this bundle. Otherwise the installed copy.
  static var applicationURL: URL? {
    if Bundle.main.bundleURL.pathExtension == "app" {
      return Bundle.main.bundleURL
    }
    let fileManager = FileManager.default
    let candidates = [
      URL(fileURLWithPath: "/Applications/Annotator.app", isDirectory: true),
      fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Annotator.app", isDirectory: true),
    ]
    return candidates.first { url in
      fileManager.isExecutableFile(atPath: url.appendingPathComponent("Contents/MacOS/Annotator").path)
    }
  }

  private static func resolved(_ url: URL) -> URL {
    url.resolvingSymlinksInPath().standardizedFileURL
  }
}
