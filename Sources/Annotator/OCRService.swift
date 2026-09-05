import AppKit
import ImageIO
import Vision

enum OCRService {
  static func warm() {
    DispatchQueue.global(qos: .userInitiated).async {
      let width = 16
      let bytes = [UInt8](repeating: 255, count: width * width * 4)
      guard let provider = CGDataProvider(data: Data(bytes) as CFData),
            let cgImage = CGImage(
              width: width,
              height: width,
              bitsPerComponent: 8,
              bitsPerPixel: 32,
              bytesPerRow: width * 4,
              space: CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
              provider: provider,
              decode: nil,
              shouldInterpolate: false,
              intent: .defaultIntent
            )
      else { return }
      _ = recognize(cgImage)
    }
  }

  static func recognize(contentsOf url: URL) -> String? {
    guard let cgImage = cgImage(contentsOf: url) else { return nil }
    return recognize(cgImage)
  }

  private static func recognize(_ cgImage: CGImage) -> String? {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true

    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    do {
      try handler.perform([request])
    } catch {
      return nil
    }

    guard let observations = request.results, !observations.isEmpty else { return nil }
    let text = cluster(observations).trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? nil : text
  }

  /// Decode the PNG at native pixel size. `NSImage.cgImage(forProposedRect:)` can
  /// downsample Retina captures to point size, which is what made OCR garbage.
  private static func cgImage(contentsOf url: URL) -> CGImage? {
    let options = [kCGImageSourceShouldCache: true] as CFDictionary
    guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else { return nil }
    if let cgImage = CGImageSourceCreateImageAtIndex(source, 0, options) {
      return cgImage
    }
    guard let image = NSImage(contentsOf: url) else { return nil }
    if let rep = image.representations
      .compactMap({ $0 as? NSBitmapImageRep })
      .max(by: { $0.pixelsWide < $1.pixelsWide })
    {
      return rep.cgImage
    }
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else {
      return nil
    }
    return rep.cgImage
  }

  private static func cluster(_ observations: [VNRecognizedTextObservation]) -> String {
    struct Item {
      let text: String
      let box: CGRect
    }

    let items: [Item] = observations.compactMap { observation in
      guard let candidate = observation.topCandidates(1).first,
            candidate.confidence >= 0.25,
            !candidate.string.isEmpty
      else { return nil }
      return Item(text: candidate.string, box: observation.boundingBox)
    }
    guard !items.isEmpty else { return "" }

    let sorted = items.sorted { a, b in
      let threshold = max(a.box.height, b.box.height) * 0.5
      if abs(a.box.midY - b.box.midY) > threshold {
        return a.box.midY > b.box.midY
      }
      return a.box.minX < b.box.minX
    }

    var lines: [[Item]] = []
    for item in sorted {
      if var last = lines.last,
         let representative = last.first,
         abs(item.box.midY - representative.box.midY)
           <= max(item.box.height, representative.box.height) * 0.6
      {
        last.append(item)
        lines[lines.count - 1] = last
      } else {
        lines.append([item])
      }
    }

    return lines
      .map { line in
        line.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ")
      }
      .joined(separator: "\n")
  }
}
