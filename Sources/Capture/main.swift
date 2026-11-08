import AppKit
import CaptureKit
import Foundation

/// Tiny AppKit process. Raycast starts this before the SwiftUI editor so the
/// crosshair does not wait on those libraries.
@main
enum CaptureMain {
  private static let delegate = HelperDelegate()

  static func main() {
    let app = NSApplication.shared
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
  }
}

private final class HelperDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    DispatchQueue.main.async {
      let args = CommandLine.arguments
      guard let outIndex = args.firstIndex(of: "--out"),
            args.index(after: outIndex) < args.endIndex
      else {
        fputs("Capture: missing --out\n", stderr)
        exit(2)
      }
      let url = URL(fileURLWithPath: args[args.index(after: outIndex)])
      let delay: Int = {
        guard let index = args.firstIndex(of: "--delay"),
              args.index(after: index) < args.endIndex
        else { return 0 }
        return Int(args[args.index(after: index)]) ?? 0
      }()

      let ok = CaptureRunner.capture(
        window: args.contains("--window"),
        delaySeconds: delay,
        fullScreen: args.contains("--fullscreen"),
        repeatLast: args.contains("--repeat"),
        locateRegion: true,
        output: url
      )
      if !ok {
        CaptureRunner.markCancelled(url)
      }
      exit(ok ? 0 : 1)
    }
  }
}
