import SwiftUI

struct ToolPaletteOverlay: View {
  let active: Tool
  let onPick: (Tool) -> Void
  let onDismiss: () -> Void

  private let ink = Color(red: 0.92, green: 0.93, blue: 0.94)
  private let muted = Color(red: 0.62, green: 0.64, blue: 0.67)
  private let surface = Color(red: 0.14, green: 0.14, blue: 0.15)
  private let accent = Color(red: 1, green: 0.23, blue: 0.19)

  var body: some View {
    ZStack {
      Color.black.opacity(0.55)
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
          .font(.system(size: layout.titleSize, weight: .semibold, design: .rounded))
          .foregroundStyle(ink)
        Spacer(minLength: 8)
          Text("Hold space · press a key")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(muted)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }

      ForEach(ToolPaletteGroup.overlay) { group in
        VStack(alignment: .leading, spacing: 6) {
          Text(group.title)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(muted)
            .textCase(.uppercase)
            .tracking(0.7)
          LazyVGrid(columns: layout.columns, alignment: .leading, spacing: layout.gap) {
            ForEach(group.tools) { tool in
              PaletteCard(
                tool: tool,
                active: active == tool,
                accent: accent,
                ink: ink,
                muted: muted,
                layout: layout
              ) {
                onPick(tool)
              }
            }
          }
        }
      }
    }
    .padding(layout.pad)
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(surface)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(Color.white.opacity(0.1), lineWidth: 1)
    )
    .onTapGesture {}
  }
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
  let tool: Tool
  let active: Bool
  let accent: Color
  let ink: Color
  let muted: Color
  let layout: PaletteLayout
  let action: () -> Void

  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      VStack(spacing: 4) {
        Text(tool.hotkey.uppercased())
          .font(.system(size: layout.keySize, weight: .bold, design: .monospaced))
          .foregroundStyle(active ? accent : ink)
          .minimumScaleFactor(0.6)
          .lineLimit(1)
        Image(systemName: tool.symbolName)
          .font(.system(size: layout.iconSize, weight: .semibold))
          .foregroundStyle(active ? accent : ink.opacity(0.9))
        Text(tool.label)
          .font(.system(size: layout.labelSize, weight: .medium, design: .rounded))
          .foregroundStyle(active ? accent.opacity(0.9) : muted)
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
          .stroke(active ? accent.opacity(0.7) : Color.white.opacity(0.08), lineWidth: 1)
      )
      .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .animation(.easeOut(duration: 0.12), value: active)
    .animation(.easeOut(duration: 0.1), value: hovering)
  }

  private var fill: Color {
    if active { return Color.white.opacity(0.12) }
    if hovering { return Color.white.opacity(0.08) }
    return Color.white.opacity(0.04)
  }
}
