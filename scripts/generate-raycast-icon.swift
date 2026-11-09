import AppKit

// Ink Trio Raycast icon.
//
// The approved master is assets/icon/ink-trio.png (1024, precomposed).
// Glass, enamel, and the frosted blur where the red ring passes behind the
// frame are in that raster. Redrawing them with AppKit shapes produces a
// flatter icon, so this script copies the master when it is already 1024
// and only resamples when a different size is requested.
//
// The system App Icon is a separate full-bleed image (assets/icon/AppIcon-1024.png)
// produced by scripts/generate-icons.py. Raycast keeps the precomposed master.

let outputPath = CommandLine.arguments.count > 1
  ? CommandLine.arguments[1]
  : "raycast/assets/icon.png"
let masterPath = CommandLine.arguments.count > 2
  ? CommandLine.arguments[2]
  : "assets/icon/ink-trio.png"
let dim = 1024

let masterURL = URL(fileURLWithPath: masterPath)
let outputURL = URL(fileURLWithPath: outputPath)
let masterData: Data
do {
  masterData = try Data(contentsOf: masterURL)
} catch {
  fputs("Missing Ink Trio master at \(masterPath). Run from the repo root.\n", stderr)
  exit(1)
}

if let rep = NSBitmapImageRep(data: masterData),
   rep.pixelsWide == dim,
   rep.pixelsHigh == dim {
  do {
    try masterData.write(to: outputURL)
  } catch {
    fputs("Could not write \(outputPath): \(error)\n", stderr)
    exit(1)
  }
  print("Wrote \(outputURL.path) (master, \(dim)px)")
  exit(0)
}

guard let image = NSImage(data: masterData),
      let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: dim,
        pixelsHigh: dim,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
      ) else {
  fputs("Could not resample \(masterPath)\n", stderr)
  exit(1)
}
rep.size = NSSize(width: dim, height: dim)

NSGraphicsContext.saveGraphicsState()
guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
  fputs("Could not open bitmap context\n", stderr)
  exit(1)
}
NSGraphicsContext.current = ctx
ctx.shouldAntialias = true
ctx.imageInterpolation = .high
image.draw(
  in: NSRect(x: 0, y: 0, width: dim, height: dim),
  from: NSRect(origin: .zero, size: image.size),
  operation: .copy,
  fraction: 1
)
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
  fputs("Could not encode PNG\n", stderr)
  exit(1)
}
do {
  try png.write(to: outputURL)
} catch {
  fputs("Could not write \(outputPath): \(error)\n", stderr)
  exit(1)
}
print("Wrote \(outputURL.path) (resampled to \(dim)px)")
