import AppKit
import Foundation

/// Shared capture paths. The Raycast helper and the editor are different
/// processes, so last-region cannot live in `UserDefaults.standard`.
public enum AnnotatorFiles {
  public static var supportDirectory: URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
    let dir = base.appendingPathComponent("Annotator", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  public static var lastRectURL: URL {
    supportDirectory.appendingPathComponent("last-rect.txt")
  }

  public static var lastShotURL: URL {
    supportDirectory.appendingPathComponent("last-shot.png")
  }

  public static var lastMarksURL: URL {
    supportDirectory.appendingPathComponent("last-marks.json")
  }
}

/// Runs `screencapture` and records the drag. No SwiftUI — the hotkey can
/// spawn this before the editor finishes loading.
public enum CaptureRunner {
  @discardableResult
  public static func capture(
    window: Bool = false,
    delaySeconds: Int = 0,
    fullScreen: Bool = false,
    repeatLast: Bool = false,
    locateRegion: Bool = true,
    output: URL
  ) -> Bool {
    if delaySeconds > 0 {
      Thread.sleep(forTimeInterval: TimeInterval(delaySeconds))
    }

    if repeatLast {
      guard let rect = storedRect() else { return false }
      return run(["-x", "-R", rectString(rect), output.path], to: output)
    }

    if fullScreen {
      let screen = screenUnderMouse()
      let quartz = quartzRect(screen.frame)
      store(quartz)
      return run(["-x", "-R", rectString(quartz), output.path], to: output)
    }

    if window {
      return run(["-x", "-w", output.path], to: output, pump: true)
    }

    let tracker: DragRectTracker? = locateRegion ? DragRectTracker() : nil
    tracker?.start()
    defer { tracker?.stop() }

    guard run(["-x", "-i", output.path], to: output, pump: true) else {
      return false
    }
    if let cocoa = tracker?.rect {
      store(quartzRect(cocoa))
    }
    return true
  }

  /// Poll until `screencapture` has finished writing `url`, or a sibling
  /// `url.cancelled` marker appears.
  public static func waitForImage(at url: URL, timeout: TimeInterval) -> Bool {
    let cancel = URL(fileURLWithPath: url.path + ".cancelled")
    let start = Date()
    var lastSize: Int64 = -1
    var stable = 0
    while Date().timeIntervalSince(start) < timeout {
      if FileManager.default.fileExists(atPath: cancel.path) {
        try? FileManager.default.removeItem(at: cancel)
        return false
      }
      if let size = fileSize(url), size > 32 {
        if size == lastSize {
          stable += 1
          if stable >= 2 { return true }
        } else {
          stable = 0
          lastSize = size
        }
      }
      RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.03))
    }
    return fileSize(url).map { $0 > 32 } ?? false
  }

  public static func markCancelled(_ url: URL) {
    let cancel = URL(fileURLWithPath: url.path + ".cancelled")
    FileManager.default.createFile(atPath: cancel.path, contents: Data())
  }

  private static func fileSize(_ url: URL) -> Int64? {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
          let size = attrs[.size] as? Int64
    else { return nil }
    return size
  }

  private static func run(_ args: [String], to url: URL, pump: Bool = false) -> Bool {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = args
    do {
      try process.run()
      if pump {
        while process.isRunning {
          RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.03))
        }
      } else {
        process.waitUntilExit()
      }
    } catch {
      return false
    }
    return process.terminationStatus == 0 && FileManager.default.fileExists(atPath: url.path)
  }

  private static func screenUnderMouse() -> NSScreen {
    let mouse = NSEvent.mouseLocation
    return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
      ?? NSScreen.main
      ?? NSScreen.screens[0]
  }

  static func quartzRect(_ cocoa: CGRect) -> CGRect {
    let top = NSScreen.screens.map(\.frame.maxY).max() ?? cocoa.maxY
    return CGRect(x: cocoa.minX, y: top - cocoa.maxY, width: cocoa.width, height: cocoa.height)
  }

  private static func rectString(_ rect: CGRect) -> String {
    "\(Int(rect.minX.rounded())),\(Int(rect.minY.rounded())),\(Int(rect.width.rounded())),\(Int(rect.height.rounded()))"
  }

  private static func store(_ rect: CGRect) {
    let raw = rectString(rect)
    try? raw.write(to: AnnotatorFiles.lastRectURL, atomically: true, encoding: .utf8)
  }

  private static func storedRect() -> CGRect? {
    if let raw = try? String(contentsOf: AnnotatorFiles.lastRectURL, encoding: .utf8),
       let rect = parse(raw)
    {
      return rect
    }
    // Older builds stored the rect in the Annotator executable's defaults.
    let legacy = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Preferences/Annotator.plist")
    if let dict = NSDictionary(contentsOf: legacy),
       let raw = dict["annotator.lastCaptureRect"] as? String,
       let rect = parse(raw)
    {
      try? raw.write(to: AnnotatorFiles.lastRectURL, atomically: true, encoding: .utf8)
      return rect
    }
    return nil
  }

  private static func parse(_ raw: String) -> CGRect? {
    let parts = raw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    guard parts.count == 4, parts[2] > 1, parts[3] > 1 else { return nil }
    return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
  }
}

/// Records the interactive `screencapture -i` drag in screen space.
final class DragRectTracker {
  private var monitor: Any?
  private var down: CGPoint?
  private(set) var rect: CGRect?

  func start() {
    down = nil
    rect = nil
    monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
      guard let self else { return }
      let point = NSEvent.mouseLocation
      if event.type == .leftMouseDown {
        self.down = point
        return
      }
      guard event.type == .leftMouseUp, let down = self.down else { return }
      let r = CGRect(
        x: min(down.x, point.x),
        y: min(down.y, point.y),
        width: abs(point.x - down.x),
        height: abs(point.y - down.y)
      )
      if r.width >= 8, r.height >= 8 {
        self.rect = r
      }
    }
  }

  func stop() {
    if let monitor {
      NSEvent.removeMonitor(monitor)
    }
    monitor = nil
  }
}
