import AppKit
import CoreImage
import SwiftUI
import UniformTypeIdentifiers

enum CaptureService {
  private static let lastRectKey = "annotator.lastCaptureRect"

  /// Interactive region, window, full display, or the last saved rect.
  static func capture(
    window: Bool = false,
    delaySeconds: Int = 0,
    fullScreen: Bool = false,
    repeatLast: Bool = false,
    locateRegion: Bool = true
  ) -> URL? {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("annotator-\(UUID().uuidString).png")

    if delaySeconds > 0 {
      Thread.sleep(forTimeInterval: TimeInterval(delaySeconds))
    }

    if repeatLast {
      if let rect = storedRect() {
        return run(["-x", "-R", rectString(rect), url.path], to: url) ? url : nil
      }
    }

    if fullScreen {
      let screen = screenUnderMouse()
      let quartz = quartzRect(screen.frame)
      store(quartz)
      return run(["-x", "-R", rectString(quartz), url.path], to: url) ? url : nil
    }

    if window {
      return run(["-x", "-w", url.path], to: url) ? url : nil
    }

    // Interactive region: show the picker immediately. Last-region storage
    // comes from the drag rect (no full-screen snapshot + pixel hunt).
    let tracker: DragRectTracker? = locateRegion ? DragRectTracker() : nil
    tracker?.start()
    defer { tracker?.stop() }

    guard run(["-x", "-i", url.path], to: url, pump: locateRegion) else {
      return nil
    }
    if let cocoa = tracker?.rect {
      store(quartzRect(cocoa))
    }
    return url
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

  private static func quartzRect(_ cocoa: CGRect) -> CGRect {
    let top = NSScreen.screens.map(\.frame.maxY).max() ?? cocoa.maxY
    return CGRect(x: cocoa.minX, y: top - cocoa.maxY, width: cocoa.width, height: cocoa.height)
  }

  private static func rectString(_ rect: CGRect) -> String {
    "\(Int(rect.minX.rounded())),\(Int(rect.minY.rounded())),\(Int(rect.width.rounded())),\(Int(rect.height.rounded()))"
  }

  private static func store(_ rect: CGRect) {
    UserDefaults.standard.set(rectString(rect), forKey: lastRectKey)
  }

  private static func storedRect() -> CGRect? {
    guard let raw = UserDefaults.standard.string(forKey: lastRectKey) else { return nil }
    let parts = raw.split(separator: ",").compactMap { Double($0) }
    guard parts.count == 4 else { return nil }
    return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
  }
}

/// Records the interactive `screencapture -i` drag in screen space so we can
/// store last-region without a full-display snapshot + brute-force search.
private final class DragRectTracker {
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

enum ImageSampler {
  static func swatch(in image: NSImage, at point: CGPoint) -> AnnotationColor? {
    guard let color = color(in: image, at: point) else { return nil }
    return nearest(color)
  }

  static func color(in image: NSImage, at point: CGPoint) -> NSColor? {
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
    let x = Int((point.x / max(image.size.width, 1) * CGFloat(rep.pixelsWide)).rounded())
    let y = Int((point.y / max(image.size.height, 1) * CGFloat(rep.pixelsHigh)).rounded())
    let cx = min(max(0, x), rep.pixelsWide - 1)
    let cy = min(max(0, y), rep.pixelsHigh - 1)
    return rep.colorAt(x: cx, y: cy)
  }

  static func nearest(_ color: NSColor) -> AnnotationColor {
    let rgb = color.usingColorSpace(.sRGB) ?? color
    var best: AnnotationColor = .red
    var bestDist = CGFloat.greatestFiniteMagnitude
    for swatch in AnnotationColor.allCases {
      let s = NSColor(swatch.swatch)
      guard let sRGB = s.usingColorSpace(.sRGB) else { continue }
      let dr = rgb.redComponent - sRGB.redComponent
      let dg = rgb.greenComponent - sRGB.greenComponent
      let db = rgb.blueComponent - sRGB.blueComponent
      let dist = dr * dr + dg * dg + db * db
      if dist < bestDist {
        bestDist = dist
        best = swatch
      }
    }
    return best
  }
}

enum ClipboardService {
  static let maxBytes = 2 * 1024 * 1024

  static func imageFromPasteboard() -> NSImage? {
    if let image = NSImage(pasteboard: NSPasteboard.general) {
      return image
    }
    let pb = NSPasteboard.general
    if let data = pb.data(forType: .png) ?? pb.data(forType: .tiff) {
      return NSImage(data: data)
    }
    return nil
  }

  static func copyString(_ text: String) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(text, forType: .string)
  }

  static func copyCompressed(_ image: NSImage) {
    guard let encoded = compress(image, maxBytes: maxBytes) else { return }
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setData(encoded.data, forType: encoded.type)
  }

  private struct EncodedImage {
    let data: Data
    let type: NSPasteboard.PasteboardType
  }

  /// Prefer PNG when small enough; otherwise JPEG with quality/scale fallbacks under maxBytes.
  private static func compress(_ image: NSImage, maxBytes: Int) -> EncodedImage? {
    guard let original = bitmapRep(from: image) else { return nil }

    if let png = original.representation(using: .png, properties: [:]), png.count <= maxBytes {
      return EncodedImage(data: png, type: .png)
    }

    var scale: CGFloat = 1.0
    var lastRep = original
    for _ in 0..<8 {
      let rep: NSBitmapImageRep
      if scale < 0.999, let scaled = resized(original, scale: scale) {
        rep = scaled
      } else {
        rep = original
      }
      lastRep = rep

      for quality in stride(from: 0.92, through: 0.35, by: -0.07) {
        let props: [NSBitmapImageRep.PropertyKey: Any] = [
          .compressionFactor: quality,
        ]
        if let jpeg = rep.representation(using: .jpeg, properties: props),
           jpeg.count <= maxBytes
        {
          return EncodedImage(data: jpeg, type: NSPasteboard.PasteboardType("public.jpeg"))
        }
      }

      scale *= 0.82
      if scale < 0.25 { break }
    }

    let props: [NSBitmapImageRep.PropertyKey: Any] = [.compressionFactor: 0.3]
    if let jpeg = lastRep.representation(using: .jpeg, properties: props) {
      return EncodedImage(data: jpeg, type: NSPasteboard.PasteboardType("public.jpeg"))
    }
    return nil
  }

  static func pngData(_ image: NSImage) -> Data? {
    guard let rep = bitmapRep(from: image) else { return nil }
    return rep.representation(using: .png, properties: [:])
  }

  static func bitmapRep(from image: NSImage) -> NSBitmapImageRep? {
    if let existing = image.representations.compactMap({ $0 as? NSBitmapImageRep })
      .max(by: { $0.pixelsWide < $1.pixelsWide })
    {
      return existing
    }
    guard let tiff = image.tiffRepresentation else { return nil }
    return NSBitmapImageRep(data: tiff)
  }

  private static func resized(_ rep: NSBitmapImageRep, scale: CGFloat) -> NSBitmapImageRep? {
    let newW = max(1, Int((CGFloat(rep.pixelsWide) * scale).rounded()))
    let newH = max(1, Int((CGFloat(rep.pixelsHigh) * scale).rounded()))
    guard let out = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: newW,
      pixelsHigh: newH,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    ) else { return nil }

    out.size = NSSize(width: newW, height: newH)
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let ctx = NSGraphicsContext(bitmapImageRep: out) else { return nil }
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high
    rep.draw(in: NSRect(x: 0, y: 0, width: newW, height: newH))
    return out
  }
}

enum ImageCropper {
  /// `rect` is in image-point coordinates with origin at the top-left (SwiftUI).
  static func crop(_ image: NSImage, to rect: CGRect) -> NSImage? {
    let r = rect.normalized
    guard r.width > 1, r.height > 1, image.size.width > 0, image.size.height > 0 else {
      return nil
    }

    var proposed = CGRect(origin: .zero, size: image.size)
    guard let cg = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
      return nil
    }

    let scaleX = CGFloat(cg.width) / image.size.width
    let scaleY = CGFloat(cg.height) / image.size.height
    let pixelRect = CGRect(
      x: r.minX * scaleX,
      y: r.minY * scaleY,
      width: r.width * scaleX,
      height: r.height * scaleY
    ).integral

    guard pixelRect.width > 1, pixelRect.height > 1,
          let cropped = cg.cropping(to: pixelRect)
    else {
      return nil
    }

    return NSImage(cgImage: cropped, size: NSSize(width: r.width, height: r.height))
  }
}

enum PixelateService {
  private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

  /// Pixelate `imageRect` (image-point, top-left origin) and return an image sized to that rect.
  static func mosaic(source: NSImage, imageRect: CGRect) -> NSImage? {
    let r = imageRect.normalized
    guard r.width > 1, r.height > 1, source.size.width > 0 else { return nil }

    var proposed = CGRect(origin: .zero, size: source.size)
    guard let cg = source.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
      return nil
    }

    let scaleX = CGFloat(cg.width) / source.size.width
    let scaleY = CGFloat(cg.height) / source.size.height
    let pixelRect = CGRect(
      x: r.minX * scaleX,
      y: r.minY * scaleY,
      width: r.width * scaleX,
      height: r.height * scaleY
    ).integral

    guard pixelRect.width > 1, pixelRect.height > 1,
          let cropped = cg.cropping(to: pixelRect)
    else {
      return nil
    }

    let input = CIImage(cgImage: cropped)
    let block = max(8, min(pixelRect.width, pixelRect.height) / 16)
    guard let filter = CIFilter(name: "CIPixellate") else { return nil }
    filter.setValue(input, forKey: kCIInputImageKey)
    filter.setValue(block, forKey: kCIInputScaleKey)
    filter.setValue(
      CIVector(x: input.extent.midX, y: input.extent.midY),
      forKey: kCIInputCenterKey
    )
    guard let output = filter.outputImage else { return nil }

    let extent = input.extent
    guard let outCG = ciContext.createCGImage(output, from: extent) else { return nil }
    return NSImage(cgImage: outCG, size: NSSize(width: r.width, height: r.height))
  }
}

struct ExportCanvas: View {
  let image: NSImage
  let annotations: [Annotation]
  let size: CGSize
  var strokeWidth: CGFloat = 2.5

  var body: some View {
    ZStack(alignment: .topLeading) {
      Image(nsImage: image)
        .resizable()
        .frame(width: size.width, height: size.height)

      AnnotationOverlay(
        annotations: annotations,
        draft: nil,
        tool: .rectangle,
        selectedID: nil,
        draftColor: .red,
        defaultStroke: strokeWidth,
        strokeScale: 1,
        sourceImage: image,
        imageSize: size
      )
      .frame(width: size.width, height: size.height)
    }
    .frame(width: size.width, height: size.height)
  }
}

enum CompositeExporter {
  @MainActor
  static func render(image: NSImage, annotations: [Annotation], strokeWidth: CGFloat) -> NSImage {
    let size = image.size
    let view = ExportCanvas(
      image: image,
      annotations: annotations,
      size: size,
      strokeWidth: strokeWidth
    )
    let renderer = ImageRenderer(content: view)
    renderer.scale = pixelScale(for: image)
    return renderer.nsImage ?? image
  }

  private static func pixelScale(for image: NSImage) -> CGFloat {
    if let rep = image.representations.compactMap({ $0 as? NSBitmapImageRep })
      .max(by: { $0.pixelsWide < $1.pixelsWide }),
      image.size.width > 0
    {
      return max(1, CGFloat(rep.pixelsWide) / image.size.width)
    }
    return 1
  }
}

enum DiskExporter {
  @MainActor
  static func savePNG(_ image: NSImage) -> Bool {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.png]
    panel.canCreateDirectories = true
    panel.isExtensionHidden = false
    panel.nameFieldStringValue = "annotated.png"
    panel.title = "Save annotated screenshot"

    let host = NSApp.windows.first { $0 is AnnotatorWindow }

    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    host?.makeKeyAndOrderFront(nil)

    let result = panel.runModal()

    var wrote = false
    if result == .OK, let url = panel.url, let data = ClipboardService.pngData(image) {
      try? data.write(to: url)
      wrote = true
    }

    NSApp.setActivationPolicy(.accessory)
    if let host {
      host.hidesOnDeactivate = false
      host.orderFrontRegardless()
      host.makeKeyAndOrderFront(nil)
    }
    NSApp.activate(ignoringOtherApps: true)
    return wrote
  }
}
