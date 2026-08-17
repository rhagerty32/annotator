import SwiftUI

enum AnnotatorChrome {
  static let minWidth: CGFloat = 1100
  static let minHeight: CGFloat = 760
  static let toolbarHeight: CGFloat = 64
  static let canvasPadding: CGFloat = 72
  static let minZoom: CGFloat = 1
  static let maxZoom: CGFloat = 16

  static let bar = Color(red: 0.11, green: 0.11, blue: 0.12)
  static let void = Color(red: 0.055, green: 0.055, blue: 0.06)
}

struct RootView: View {
  @ObservedObject var state: AppState

  private let barBG = AnnotatorChrome.bar
  private let ink = Color(red: 0.92, green: 0.93, blue: 0.94)
  private let muted = Color(red: 0.62, green: 0.64, blue: 0.67)
  private let accent = Color(red: 1, green: 0.23, blue: 0.19)

  private let markTools: [Tool] = [.select, .rectangle, .circle, .arrow, .draw, .text]
  private let calloutTools: [Tool] = [.highlight, .spotlight, .numbered]
  private let cutTools: [Tool] = [.redact, .crop]

  @State private var settingsAnchor: CGRect = .zero

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
    .background(state.stage == .chrome ? AnnotatorChrome.bar : AnnotatorChrome.void)
    .coordinateSpace(name: "annotator-root")
    .overlay(alignment: .topLeading) {
      if state.showSettings {
        StageSettingsPopover(state: state)
          .padding(.leading, settingsAnchor.minX)
          .padding(.top, settingsAnchor.maxY + 6)
      }
    }
    .onPreferenceChange(SettingsAnchorKey.self) { frame in
      DispatchQueue.main.async { settingsAnchor = frame }
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

      Spacer(minLength: 12)

      HStack(spacing: 8) {
        toolCluster(markTools)
        toolCluster(calloutTools)
        toolCluster(cutTools)
      }
      .fixedSize()

      Spacer(minLength: 12)

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
    .padding(.horizontal, 16)
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
      Text("⌘C copy · pinch/scroll zoom · space pan")
        .font(.system(size: 11))
        .foregroundStyle(muted.opacity(0.75))
        .lineLimit(1)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 7)
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
            .frame(width: 16, height: 16)
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

  private func toolCluster(_ tools: [Tool]) -> some View {
    HStack(spacing: 1) {
      ForEach(tools) { tool in
        ToolChip(
          tool: tool,
          active: state.tool == tool,
          accent: accent,
          muted: muted,
          ink: ink,
          enabled: !state.isTyping
        ) {
          state.selectTool(tool)
        }
      }
    }
    .padding(4)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color.white.opacity(0.06))
    )
  }
}

private struct ToolChip: View {
  let tool: Tool
  let active: Bool
  let accent: Color
  let muted: Color
  let ink: Color
  let enabled: Bool
  let action: () -> Void

  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      VStack(spacing: 2) {
        Text(tool.hotkey.uppercased())
          .font(.system(size: 11, weight: .bold, design: .monospaced))
          .foregroundStyle(active ? accent : ink.opacity(0.88))
        Text(tool.label)
          .font(.system(size: 8.5, weight: .medium, design: .rounded))
          .foregroundStyle(active ? accent.opacity(0.9) : muted.opacity(0.82))
          .tracking(0.2)
          .lineLimit(1)
          .fixedSize(horizontal: true, vertical: false)
      }
      .padding(.horizontal, 8)
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
