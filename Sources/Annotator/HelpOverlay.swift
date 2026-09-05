import SwiftUI

struct HelpOverlay: View {
  var onDismiss: () -> Void

  private let ink = Color(red: 0.92, green: 0.93, blue: 0.94)
  private let muted = Color(red: 0.62, green: 0.64, blue: 0.67)
  private let surface = Color(red: 0.14, green: 0.14, blue: 0.15)
  private let chip = Color.white.opacity(0.08)

  var body: some View {
    ZStack {
      Color.black.opacity(0.5)
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)

      VStack(alignment: .leading, spacing: 18) {
        HStack(alignment: .firstTextBaseline) {
          Text("Shortcuts")
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(ink)
          Spacer()
          Text("Esc or ? to close")
            .font(.system(size: 11))
            .foregroundStyle(muted)
        }

        section("Tools", rows: [
          [("Space", "Hold for tools"), ("?", "All shortcuts")],
          [("V", "Select"), ("R", "Rectangle"), ("C", "Circle"), ("A", "Arrow")],
          [("L", "Line"), ("D", "Draw"), ("X", "Cross"), ("T", "Text")],
          [("H", "Fill"), ("I", "Spotlight"), ("N", "Steps")],
          [("B", "Redact"), ("K", "Crop")],
        ])

        section("While drawing", rows: [
          [("⇧", "Square / 45°"), ("⌥", "Center / invert"), ("[ ]", "Stroke")],
          [("1–0", "Colors"), ("⌥-click", "Eyedropper")],
        ])

        section("Edit", rows: [
          [("⌘Z", "Undo"), ("⇧⌘Z", "Redo"), ("⌫", "Delete")],
          [("↑↓←→", "Nudge"), ("⌘D", "Duplicate"), ("⌘[ ]", "Order")],
          [("Mid", "Curve arrow"), ("Dot", "Round rect")],
          [("Esc", "Deselect / cancel"), ("↩", "Edit text")],
        ])

        section("View", rows: [
          [("Pinch", "Zoom"), ("Scroll", "Zoom")],
          [("⌘+", "Zoom in"), ("⌘-", "Zoom out"), ("⌘0", "Reset")],
        ])

        section("Save", rows: [
          [("S", "Copy & close"), ("⌘C", "Copy, stay"), ("⇧S", "Save PNG")],
        ])
      }
      .padding(22)
      .frame(maxWidth: 560)
      .background(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(surface)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(Color.white.opacity(0.08), lineWidth: 1)
      )
      .onTapGesture {}
    }
  }

  private func section(_ title: String, rows: [[(String, String)]]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(muted)
        .textCase(.uppercase)
        .tracking(0.6)

      VStack(alignment: .leading, spacing: 6) {
        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
          HStack(spacing: 14) {
            ForEach(Array(row.enumerated()), id: \.offset) { _, item in
              shortcut(item.0, item.1)
            }
            Spacer(minLength: 0)
          }
        }
      }
    }
  }

  private func shortcut(_ key: String, _ label: String) -> some View {
    HStack(spacing: 6) {
      Text(key)
        .font(.system(size: 11, weight: .bold, design: .monospaced))
        .foregroundStyle(ink)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
          RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(chip)
        )
      Text(label)
        .font(.system(size: 12))
        .foregroundStyle(muted)
        .fixedSize()
    }
  }
}
