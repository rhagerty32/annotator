import AppKit
import CaptureKit
import Foundation

/// Turns a launch request into an image for the editor. Does not exit.
enum SessionLoader {
  struct LoadedImage {
    let image: NSImage
    let url: URL?
    var cgImage: CGImage?
    var annotations: [Annotation] = []
    var remembersSession = false
  }

  static func load(_ request: LaunchRequest) -> Result<LoadedImage, SessionError> {
    switch request {
    case .clipboard:
      guard let image = ClipboardService.imageFromPasteboard(),
            let loaded = ShotLoader.load(nsImage: image)
      else {
        return .failure(SessionError(message: "no image on the clipboard.", code: 1))
      }
      return .success(LoadedImage(image: loaded.image, url: nil, cgImage: loaded.cgImage, remembersSession: true))

    case .reopen:
      guard let session = LastSession.load() else {
        return .failure(SessionError(message: "no last shot.", code: 1))
      }
      let loaded = ShotLoader.load(nsImage: session.image)
      return .success(LoadedImage(
        image: session.image,
        url: nil,
        cgImage: loaded?.cgImage,
        annotations: session.annotations,
        remembersSession: true
      ))

    case .capture(let options):
      guard let url = CaptureService.capture(
        window: options.window,
        delaySeconds: options.delay,
        fullScreen: options.fullScreen,
        repeatLast: options.repeatLast
      ), let loaded = ShotLoader.load(url: url) else {
        return .failure(SessionError(message: "capture cancelled or failed.", code: 1))
      }
      return .success(LoadedImage(image: loaded.image, url: url, cgImage: loaded.cgImage, remembersSession: true))

    case .image(let path, let wait):
      let url = URL(fileURLWithPath: path)
      if wait, !CaptureRunner.waitForImage(at: url, timeout: 180) {
        return .failure(SessionError(message: "capture cancelled or failed.", code: 0, silent: true))
      }
      guard let loaded = ShotLoader.load(url: url) else {
        return .failure(SessionError(message: "could not load image at \(path)", code: 1))
      }
      return .success(LoadedImage(image: loaded.image, url: url, cgImage: loaded.cgImage, remembersSession: true))

    case .file(let path):
      let url = URL(fileURLWithPath: path)
      guard let loaded = ShotLoader.load(url: url) else {
        return .failure(SessionError(message: "could not load image at \(path)", code: 1))
      }
      return .success(LoadedImage(image: loaded.image, url: url, cgImage: loaded.cgImage, remembersSession: true))

    case .agent, .activate, .settings, .updates, .ocr:
      return .failure(SessionError(message: "nothing to open.", code: 1))
    }
  }
}
