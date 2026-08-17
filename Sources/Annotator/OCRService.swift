import AppKit
import Vision

enum OCRService {
  static func recognize(_ image: NSImage) -> String? {
    guard let cgImage = cgImage(from: image) else { return nil }

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

  private static func cgImage(from image: NSImage) -> CGImage? {
    var rect = CGRect(origin: .zero, size: image.size)
    if let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
      return cgImage
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
      guard let text = observation.topCandidates(1).first?.string, !text.isEmpty else { return nil }
      return Item(text: text, box: observation.boundingBox)
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
