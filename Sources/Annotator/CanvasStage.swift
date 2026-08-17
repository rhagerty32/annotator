import SwiftUI

enum CanvasStage: String, CaseIterable, Identifiable {
  case void
  case chrome
  case checker

  var id: String { rawValue }

  var title: String {
    switch self {
    case .void: return "Void"
    case .chrome: return "One metal"
    case .checker: return "Checkerboard"
    }
  }

  var blurb: String {
    switch self {
    case .void: return "Black stage, shot floats"
    case .chrome: return "Canvas matches the toolbar"
    case .checker: return "Transparency grid"
    }
  }

  var fill: Color {
    switch self {
    case .void: return AnnotatorChrome.void
    case .chrome: return AnnotatorChrome.bar
    case .checker: return Color(red: 0.17, green: 0.17, blue: 0.18)
    }
  }
}
