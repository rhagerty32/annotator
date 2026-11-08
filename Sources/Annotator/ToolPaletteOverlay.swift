import AppKit
import SwiftUI

struct ToolPaletteOverlay: View {
  let active: Tool
  let redactStyle: RedactStyle
  let onPick: (Tool) -> Void
  let onRedact: (RedactStyle) -> Void
  let onDismiss: () -> Void

  private let accent = Color.accentColor

  var body: some View {
    ZStack {
      Color.black.opacity(0.28)
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)

      GeometryReader { geo in
        let layout = PaletteLayout(in: geo.size)
        palette(layout)
          .frame(width: layout.panelWidth)
          .fixedSize(horizontal: false, vertical: true)
          .position(x: geo.size.width / 2, y: geo.size.height / 2)
      }
    }
    .ignoresSafeArea()
  }

  @ViewBuilder
  private func palette(_ layout: PaletteLayout) -> some View {
    VStack(alignment: .leading, spacing: layout.sectionGap) {
      HStack(alignment: .firstTextBaseline) {
        Text("Tools")
          .font(.system(size: layout.titleSize, weight: .semibold))
          .foregroundStyle(.primary)
        Spacer(minLength: 8)
          Text("Hold space · press a key")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }

      ForEach(ToolPaletteGroup.overlay) { group in
        VStack(alignment: .leading, spacing: 6) {
          Text(group.title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.7)
          LazyVGrid(columns: layout.columns, alignment: .leading, spacing: layout.gap) {
            ForEach(entries(in: group)) { entry in
              PaletteCard(
                keyLabel: entry.key,
                symbol: entry.symbol,
                title: entry.title,
                active: entry.active,
                accent: accent,
                layout: layout,
                action: entry.action
              )
            }
          }
        }
      }
    }
    .padding(layout.pad)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
    )
    .shadow(color: .black.opacity(0.22), radius: 28, y: 14)
    .onTapGesture {}
  }

  private func entries(in group: ToolPaletteGroup) -> [PaletteEntry] {
    group.tools.flatMap { tool in
      if tool == .redact {
        return [
          PaletteEntry(
            id: "pixelate",
            key: "B",
            symbol: RedactStyle.pixelate.symbolName,
            title: "Pixelate",
            active: active == .redact && redactStyle == .pixelate
          ) { onRedact(.pixelate) },
          PaletteEntry(
            id: "blur",
            key: "B",
            symbol: RedactStyle.blur.symbolName,
            title: "Blur",
            active: active == .redact && redactStyle == .blur
          ) { onRedact(.blur) },
        ]
      }
      return [
        PaletteEntry(
          id: tool.id,
          key: tool.hotkey.uppercased(),
          symbol: tool.symbolName,
          title: tool.label,
          active: active == tool
        ) { onPick(tool) },
      ]
    }
  }
}

private struct PaletteEntry: Identifiable {
  let id: String
  let key: String
  let symbol: String
  let title: String
  let active: Bool
  let action: () -> Void
}

private struct PaletteLayout {
  let columns: [GridItem]
  let gap: CGFloat
  let pad: CGFloat
  let sectionGap: CGFloat
  let panelWidth: CGFloat
  let cardHeight: CGFloat
  let keySize: CGFloat
  let iconSize: CGFloat
  let labelSize: CGFloat
  let titleSize: CGFloat

  init(in size: CGSize) {
    let margin: CGFloat = 24
    let availW = max(280, size.width - margin * 2)
    let availH = max(240, size.height - margin * 2)
    let compact = availW < 640 || availH < 520
    pad = compact ? 14 : 20
    gap = compact ? 6 : 8
    sectionGap = compact ? 10 : 14
    titleSize = compact ? 17 : 20
    panelWidth = min(compact ? 540 : 620, availW)

    columns = Array(
      repeating: GridItem(.flexible(minimum: 44), spacing: gap),
      count: 6
    )

    let chrome: CGFloat = pad * 2 + 28 + 4 * 18 + sectionGap * 3
    let fitted = floor((availH - chrome) / 4)
    cardHeight = min(compact ? 82 : 92, max(56, fitted))
    keySize = min(26, max(15, cardHeight * 0.28))
    iconSize = min(15, max(11, cardHeight * 0.16))
    labelSize = min(11, max(9, cardHeight * 0.12))
  }
}

private struct PaletteCard: View {
  let keyLabel: String
  let symbol: String
  let title: String
  let active: Bool
  let accent: Color
  let layout: PaletteLayout
  let action: () -> Void

  init(
    tool: Tool,
    active: Bool,
    accent: Color,
    layout: PaletteLayout,
    action: @escaping () -> Void
  ) {
    self.keyLabel = tool.hotkey.uppercased()
    self.symbol = tool.symbolName
    self.title = tool.label
    self.active = active
    self.accent = accent
    self.layout = layout
    self.action = action
  }

  init(
    keyLabel: String,
    symbol: String,
    title: String,
    active: Bool,
    accent: Color,
    layout: PaletteLayout,
    action: @escaping () -> Void
  ) {
    self.keyLabel = keyLabel
    self.symbol = symbol
    self.title = title
    self.active = active
    self.accent = accent
    self.layout = layout
    self.action = action
  }

  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      VStack(spacing: 4) {
        Text(keyLabel)
          .font(.system(size: layout.keySize, weight: .bold, design: .monospaced))
          .foregroundStyle(active ? accent : Color.primary)
          .minimumScaleFactor(0.6)
          .lineLimit(1)
        Image(systemName: symbol)
          .font(.system(size: layout.iconSize, weight: .semibold))
          .foregroundStyle(active ? accent : Color.primary)
        Text(title)
          .font(.system(size: layout.labelSize, weight: .medium))
          .foregroundStyle(active ? accent : Color.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
      }
      .frame(maxWidth: .infinity)
      .frame(height: layout.cardHeight)
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(fill)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .strokeBorder(active ? accent.opacity(0.85) : Color.primary.opacity(0.08), lineWidth: 1)
      )
      .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .animation(.easeOut(duration: 0.12), value: active)
    .animation(.easeOut(duration: 0.1), value: hovering)
  }

  private var fill: Color {
    if active { return Color.primary.opacity(0.12) }
    if hovering { return Color.primary.opacity(0.07) }
    return Color.primary.opacity(0.04)
  }
}
