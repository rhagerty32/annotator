import AppKit
import CaptureKit
import Foundation

/// The last shot and its marks. Escape deletes the temp capture, not this copy.
/// The next capture overwrites it.
enum LastSession {
  static var hasShot: Bool {
    FileManager.default.fileExists(atPath: AnnotatorFiles.lastShotURL.path)
  }

  static func save(image: NSImage, annotations: [Annotation]) {
    if let data = ClipboardService.pngData(image) {
      try? data.write(to: AnnotatorFiles.lastShotURL, options: .atomic)
    }
    saveMarks(annotations)
  }

  static func saveMarks(_ annotations: [Annotation]) {
    let payload = annotations.map { MarkArchive.dump($0) }
    guard JSONSerialization.isValidJSONObject(payload),
          let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
    else { return }
    try? data.write(to: AnnotatorFiles.lastMarksURL, options: .atomic)
  }

  static func load() -> (image: NSImage, annotations: [Annotation])? {
    guard let loaded = ShotLoader.load(url: AnnotatorFiles.lastShotURL) else { return nil }
    let marks: [Annotation]
    if let data = try? Data(contentsOf: AnnotatorFiles.lastMarksURL) {
      marks = MarkArchive.load(data)
    } else {
      marks = []
    }
    return (loaded.image, marks)
  }
}

enum MarkArchive {
  static func dump(_ annotation: Annotation) -> [String: Any] {
    var record: [String: Any] = [
      "id": annotation.id.uuidString,
      "color": annotation.color.rawValue,
      "stroke": Double(annotation.strokeWidth),
    ]
    switch annotation.kind {
    case let .rectangle(rect, radius):
      record["kind"] = "rectangle"
      record["rect"] = quad(rect)
      record["radius"] = Double(radius)
    case let .circle(rect):
      record["kind"] = "circle"
      record["rect"] = quad(rect)
    case let .cross(rect):
      record["kind"] = "cross"
      record["rect"] = quad(rect)
    case let .highlight(rect):
      record["kind"] = "highlight"
      record["rect"] = quad(rect)
    case let .spotlight(rect):
      record["kind"] = "spotlight"
      record["rect"] = quad(rect)
    case let .redact(rect, style):
      record["kind"] = "redact"
      record["rect"] = quad(rect)
      record["style"] = style.rawValue
    case let .arrow(start, end, control, headed):
      record["kind"] = "arrow"
      record["start"] = pair(start)
      record["end"] = pair(end)
      if let control { record["control"] = pair(control) }
      record["headed"] = headed
    case let .path(points):
      record["kind"] = "path"
      record["points"] = points.map { pair($0) }
    case let .text(origin, width, fontSize, string):
      record["kind"] = "text"
      record["origin"] = pair(origin)
      record["width"] = Double(width)
      record["fontSize"] = Double(fontSize)
      record["string"] = string
    case let .badge(origin, index):
      record["kind"] = "badge"
      record["origin"] = pair(origin)
      record["index"] = index
    }
    return record
  }

  static func load(_ data: Data) -> [Annotation] {
    guard let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
      return []
    }
    return rows.compactMap(parse)
  }

  private static func parse(_ record: [String: Any]) -> Annotation? {
    guard let kindName = record["kind"] as? String,
          let color = AnnotationColor(rawValue: record["color"] as? String ?? ""),
          let id = UUID(uuidString: record["id"] as? String ?? UUID().uuidString)
    else { return nil }
    let stroke = CGFloat(record["stroke"] as? Double ?? 3)
    guard let kind = kind(named: kindName, record: record) else { return nil }
    return Annotation(id: id, kind: kind, color: color, strokeWidth: stroke)
  }

  private static func kind(named name: String, record: [String: Any]) -> Annotation.Kind? {
    switch name {
    case "rectangle":
      guard let rect = rect(record["rect"]) else { return nil }
      return .rectangle(rect, radius: CGFloat(record["radius"] as? Double ?? 0))
    case "circle":
      guard let rect = rect(record["rect"]) else { return nil }
      return .circle(rect)
    case "cross":
      guard let rect = rect(record["rect"]) else { return nil }
      return .cross(rect)
    case "highlight":
      guard let rect = rect(record["rect"]) else { return nil }
      return .highlight(rect)
    case "spotlight":
      guard let rect = rect(record["rect"]) else { return nil }
      return .spotlight(rect)
    case "redact":
      guard let rect = rect(record["rect"]) else { return nil }
      let style = RedactStyle(rawValue: record["style"] as? String ?? "") ?? .pixelate
      return .redact(rect, style: style)
    case "arrow":
      guard let start = point(record["start"]), let end = point(record["end"]) else { return nil }
      return .arrow(
        start: start,
        end: end,
        control: point(record["control"]),
        headed: record["headed"] as? Bool ?? true
      )
    case "path":
      let points = (record["points"] as? [[Double]])?.compactMap { pair -> CGPoint? in
        guard pair.count == 2 else { return nil }
        return CGPoint(x: pair[0], y: pair[1])
      } ?? []
      return .path(points)
    case "text":
      guard let origin = point(record["origin"]) else { return nil }
      let width = CGFloat(record["width"] as? Double ?? 220)
      let font = CGFloat(record["fontSize"] as? Double ?? 21)
      return .text(
        origin: origin,
        width: width,
        fontSize: font,
        string: record["string"] as? String ?? ""
      )
    case "badge":
      guard let origin = point(record["origin"]) else { return nil }
      return .badge(origin: origin, index: record["index"] as? Int ?? 1)
    default:
      return nil
    }
  }

  private static func pair(_ point: CGPoint) -> [Double] {
    [Double(point.x), Double(point.y)]
  }

  private static func quad(_ rect: CGRect) -> [Double] {
    [Double(rect.origin.x), Double(rect.origin.y), Double(rect.width), Double(rect.height)]
  }

  private static func point(_ value: Any?) -> CGPoint? {
    guard let pair = value as? [Double], pair.count == 2 else { return nil }
    return CGPoint(x: pair[0], y: pair[1])
  }

  private static func rect(_ value: Any?) -> CGRect? {
    guard let quad = value as? [Double], quad.count == 4 else { return nil }
    return CGRect(x: quad[0], y: quad[1], width: quad[2], height: quad[3])
  }
}
