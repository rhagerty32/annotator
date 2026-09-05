import SwiftUI

enum AnnotatorChrome {
  static let minWidth: CGFloat = 780
  static let minHeight: CGFloat = 640
  /// Space for the traffic lights under `fullSizeContentView`.
  static let trafficLightsInset: CGFloat = 78
  static let toolbarHeight: CGFloat = 70
  static let statusBarHeight: CGFloat = 34
  static let canvasPadding: CGFloat = 72
  static let minZoom: CGFloat = 1
  static let maxZoom: CGFloat = 16

  /// Padding around the shot inside the canvas. Keep in sync with `CanvasTransform.fitted`.
  static var canvasInset: CGFloat { canvasPadding / 2 }

  /// Size the window to the shot (plus chrome), clamped to the visible screen.
  static func windowSize(for image: NSSize, visible: NSRect) -> NSSize {
    let chrome = NSSize(
      width: canvasInset * 2,
      height: toolbarHeight + statusBarHeight + canvasInset * 2 + 2
    )
    let margin: CGFloat = 28
    let maxW = max(minWidth, visible.width - margin * 2)
    let maxH = max(minHeight, visible.height - margin * 2)
    return NSSize(
      width: min(maxW, max(minWidth, image.width + chrome.width)),
      height: min(maxH, max(minHeight, image.height + chrome.height))
    )
  }

  static let bar = Color(red: 0.11, green: 0.11, blue: 0.12)
  static let void = Color(red: 0.055, green: 0.055, blue: 0.06)
}

struct RootView: View {
  @ObservedObject var state: AppState

  private let barBG = AnnotatorChrome.bar
  private let ink = Color(red: 0.92, green: 0.93, blue: 0.94)
  private let muted = Color(red: 0.62, green: 0.64, blue: 0.67)
  private let accent = Color(red: 1, green: 0.23, blue: 0.19)

  private let toolGroups: [ToolPaletteGroup] = ToolPaletteGroup.toolbar

  @State private var settingsAnchor: CGRect = .zero
  @State private var groupFace: [String: Tool] = [
    "shapes": .rectangle,
    "callouts": .highlight,
    "cut": .redact,
  ]
  @State private var openGroupID: String?

  var body: some View {
    VStack(spacing: 0) {
      toolBar
      Divider().overlay(Color.white.opacity(0.08))
      ZStack {
        AnnotationCanvasView(state: state)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        if state.showSettings {
          Color.clear
            .contentShape(Rectangle())
            .onTapGesture { state.showSettings = false }
        }
        if state.showHelp {
          HelpOverlay(onDismiss: { state.toggleHelp() })
        }
      }
      Divider().overlay(Color.white.opacity(0.08))
      statusBar
    }
    .frame(minWidth: AnnotatorChrome.minWidth, minHeight: AnnotatorChrome.minHeight)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(state.stage == .chrome ? AnnotatorChrome.bar : AnnotatorChrome.void)
    .coordinateSpace(name: "annotator-root")
    .overlay(alignment: .topLeading) {
      if state.showSettings {
        StageSettingsPopover(state: state)
          .padding(.leading, settingsAnchor.minX)
          .padding(.top, settingsAnchor.maxY + 6)
      }
    }
    .overlay {
      if state.showToolPalette {
        ToolPaletteOverlay(
          active: state.tool,
          onPick: { state.pickToolFromPalette($0) },
          onDismiss: { state.hideToolPalette() }
        )
      }
    }
    .onPreferenceChange(SettingsAnchorKey.self) { frame in
      DispatchQueue.main.async { settingsAnchor = frame }
    }
    .onChange(of: state.tool) { _, tool in
      remember(tool)
    }
    .onChange(of: state.showToolPalette) { _, open in
      if open { openGroupID = nil }
    }
  }

  private var toolBar: some View {
    HStack(spacing: 0) {
      Text("Annotator")
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .foregroundStyle(ink)
        .fixedSize()

      Button {
        state.toggleHelp()
      } label: {
        Text("?")
          .font(.system(size: 11, weight: .bold, design: .rounded))
          .foregroundStyle(state.showHelp ? ink : muted)
          .frame(width: 20, height: 20)
          .background(
            Circle()
              .fill(state.showHelp ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
          )
          .overlay(
            Circle()
              .stroke(
                state.showHelp ? accent.opacity(0.7) : Color.white.opacity(0.12),
                lineWidth: 1
              )
          )
      }
      .buttonStyle(.plain)
      .help("Shortcuts (?)")
      .padding(.leading, 8)

      Button {
        state.toggleSettings()
      } label: {
        Image(systemName: "gearshape")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(state.showSettings ? ink : muted)
          .frame(width: 20, height: 20)
          .background(
            Circle()
              .fill(state.showSettings ? Color.white.opacity(0.12) : Color.white.opacity(0.06))
          )
          .overlay(
            Circle()
              .stroke(
                state.showSettings ? accent.opacity(0.7) : Color.white.opacity(0.12),
                lineWidth: 1
              )
          )
      }
      .buttonStyle(.plain)
      .help("Stage (⌘,)")
      .padding(.leading, 4)
      .background(
        GeometryReader { geo in
          Color.clear.preference(
            key: SettingsAnchorKey.self,
            value: geo.frame(in: .named("annotator-root"))
          )
        }
      )

      Spacer(minLength: 10)

      HStack(spacing: 8) {
        standaloneTool(.select)
        ForEach(toolGroups) { group in
          groupedTools(group)
        }
      }
      .fixedSize()

      Spacer(minLength: 10)

      colorPalette
        .fixedSize()

      Spacer(minLength: 12)

      Button {
        state.saveAndQuit()
      } label: {
        Text("Save")
          .font(.system(size: 12, weight: .semibold))
          .padding(.horizontal, 14)
          .padding(.vertical, 7)
      }
      .buttonStyle(.plain)
      .foregroundStyle(.white)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(accent)
      )
      .fixedSize()
      .disabled(state.isTyping)
      .opacity(state.isTyping ? 0.45 : 1)
      .help("Copy to clipboard and close (S)")
    }
    .padding(.leading, AnnotatorChrome.trafficLightsInset)
    .padding(.trailing, 16)
    .padding(.vertical, 8)
    .frame(minHeight: AnnotatorChrome.toolbarHeight)
    .background(barBG)
  }

  private var statusBar: some View {
    HStack(spacing: 12) {
      Text(state.statusMessage)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(muted)
        .lineLimit(1)
      Spacer(minLength: 8)
      if state.zoom > 1.01 {
        Text("\(Int((state.zoom * 100).rounded()))%")
          .font(.system(size: 11, weight: .medium, design: .monospaced))
          .foregroundStyle(muted)
      }
      Text("Hold space for tools · ⌘C copy · pinch zoom")
        .font(.system(size: 11))
        .foregroundStyle(muted.opacity(0.75))
        .lineLimit(1)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 7)
    .background(barBG)
  }

  private func remember(_ tool: Tool) {
    for group in toolGroups where group.tools.contains(tool) {
      groupFace[group.id] = tool
    }
  }

  private func pick(_ tool: Tool) {
    remember(tool)
    openGroupID = nil
    state.selectTool(tool)
  }

  private func face(for group: ToolPaletteGroup) -> Tool {
    if group.tools.contains(state.tool) { return state.tool }
    return groupFace[group.id] ?? group.tools[0]
  }

  private func standaloneTool(_ tool: Tool) -> some View {
    VStack(spacing: 3) {
      Text(" ")
        .font(.system(size: 8, weight: .semibold))
        .hidden()
      ToolChip(
        tool: tool,
        active: state.tool == tool,
        compact: true,
        accent: accent,
        muted: muted,
        ink: ink,
        enabled: !state.isTyping
      ) {
        pick(tool)
      }
    }
  }

  private func groupedTools(_ group: ToolPaletteGroup) -> some View {
    let shown = face(for: group)
    let active = group.tools.contains(state.tool)
    return VStack(spacing: 3) {
      Text(group.title)
        .font(.system(size: 8, weight: .semibold, design: .rounded))
        .foregroundStyle(muted.opacity(0.85))
        .textCase(.uppercase)
        .tracking(0.7)
      HStack(spacing: 0) {
        ToolChip(
          tool: shown,
          active: active,
          compact: true,
          accent: accent,
          muted: muted,
          ink: ink,
          enabled: !state.isTyping
        ) {
          pick(shown)
        }
        Button {
          openGroupID = openGroupID == group.id ? nil : group.id
        } label: {
          Image(systemName: "chevron.down")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(active ? accent : muted)
            .frame(width: 18, height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(group.title) tools")
        .disabled(state.isTyping)
      }
      .padding(.trailing, 2)
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(Color.white.opacity(0.06))
      )
      .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .stroke(active ? accent.opacity(0.55) : Color.clear, lineWidth: 1)
      )
      .popover(isPresented: openBinding(for: group.id), arrowEdge: .bottom) {
        groupMenu(group)
      }
    }
  }

  private func openBinding(for id: String) -> Binding<Bool> {
    Binding(
      get: { openGroupID == id },
      set: { openGroupID = $0 ? id : nil }
    )
  }

  private func groupMenu(_ group: ToolPaletteGroup) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(group.title)
        .font(.system(size: 10, weight: .semibold, design: .rounded))
        .foregroundStyle(muted)
        .textCase(.uppercase)
        .tracking(0.6)
        .padding(.horizontal, 8)
        .padding(.bottom, 4)
      ForEach(group.tools) { tool in
        Button {
          pick(tool)
        } label: {
          HStack(spacing: 8) {
            Image(systemName: tool.symbolName)
              .font(.system(size: 11, weight: .semibold))
              .frame(width: 16)
            Text(tool.label)
              .font(.system(size: 12, weight: .medium))
            Spacer(minLength: 12)
            Text(tool.hotkey.uppercased())
              .font(.system(size: 11, weight: .bold, design: .monospaced))
              .foregroundStyle(state.tool == tool ? accent : muted)
          }
          .foregroundStyle(state.tool == tool ? accent : ink)
          .padding(.horizontal, 8)
          .padding(.vertical, 6)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
              .fill(state.tool == tool ? Color.white.opacity(0.12) : Color.clear)
          )
          .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
      }
    }
    .padding(8)
    .frame(minWidth: 176, alignment: .leading)
    .background(barBG)
  }

  private var colorPalette: some View {
    HStack(spacing: 6) {
      ForEach(AnnotationColor.allCases) { color in
        Button {
          state.setColor(color)
        } label: {
          Circle()
            .fill(color.swatch)
            .frame(width: 14, height: 14)
            .overlay(
              Circle()
                .stroke(Color.black.opacity(0.35), lineWidth: 0.5)
            )
            .overlay(
              Circle()
                .stroke(
                  state.activeColor == color ? Color.white : Color.clear,
                  lineWidth: 2
                )
                .padding(-2)
            )
        }
        .buttonStyle(.plain)
        .help("\(color.rawValue.capitalized) (\(color.digitHotkey))")
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 11)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color.white.opacity(0.06))
    )
  }
}

private struct ToolChip: View {
  let tool: Tool
  let active: Bool
  var compact: Bool = false
  let accent: Color
  let muted: Color
  let ink: Color
  let enabled: Bool
  let action: () -> Void

  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      VStack(spacing: 2) {
        Image(systemName: tool.symbolName)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(active ? accent : ink.opacity(0.9))
          .frame(height: 13)
        Text(tool.hotkey.uppercased())
          .font(.system(size: 9, weight: .bold, design: .monospaced))
          .foregroundStyle(active ? accent.opacity(0.95) : muted)
      }
      .frame(minWidth: compact ? 28 : 36)
      .padding(.horizontal, compact ? 7 : 8)
      .padding(.top, 5)
      .padding(.bottom, 4)
      .background(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(chipFill)
      )
      .overlay(
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .stroke(active ? accent.opacity(0.7) : Color.clear, lineWidth: 1)
      )
    }
    .buttonStyle(.plain)
    .help("\(tool.label) (\(tool.hotkey.uppercased()))")
    .disabled(!enabled)
    .opacity(enabled ? 1 : 0.4)
    .onHover { hovering = $0 }
    .animation(.easeOut(duration: 0.12), value: active)
    .animation(.easeOut(duration: 0.1), value: hovering)
  }

  private var chipFill: Color {
    if active { return Color.white.opacity(0.12) }
    if hovering && enabled { return Color.white.opacity(0.07) }
    return Color.clear
  }
}

private struct SettingsAnchorKey: PreferenceKey {
  static var defaultValue: CGRect = .zero

  static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
    let next = nextValue()
    if next != .zero { value = next }
  }
}
