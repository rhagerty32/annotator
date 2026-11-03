import AppKit
import SwiftUI

enum AnnotatorChrome {
  static let minWidth: CGFloat = 780
  static let minHeight: CGFloat = 640
  /// Unified titlebar height. Content size excludes it; used to keep the frame on screen.
  static let toolbarAllowance: CGFloat = 52
  static let statusBarHeight: CGFloat = 26
  static let canvasPadding: CGFloat = 72
  static let minZoom: CGFloat = 1
  static let maxZoom: CGFloat = 16

  /// Padding around the shot inside the canvas. Keep in sync with `CanvasTransform.fitted`.
  static var canvasInset: CGFloat { canvasPadding / 2 }

  static var contentMinHeight: CGFloat { minHeight - toolbarAllowance }

  /// Size the content view to the shot (plus the status bar), clamped to the visible screen.
  /// The system toolbar sits outside this rect.
  static func windowSize(for image: NSSize, visible: NSRect) -> NSSize {
    let chrome = NSSize(
      width: canvasInset * 2,
      height: statusBarHeight + canvasInset * 2
    )
    let margin: CGFloat = 28
    let maxW = max(minWidth, visible.width - margin * 2)
    let maxH = max(contentMinHeight, visible.height - margin * 2 - toolbarAllowance)
    return NSSize(
      width: min(maxW, max(minWidth, image.width + chrome.width)),
      height: min(maxH, max(contentMinHeight, image.height + chrome.height))
    )
  }

  static let void = Color(red: 0.055, green: 0.055, blue: 0.06)
}

struct RootView: View {
  @ObservedObject var state: AppState

  private let toolGroups: [ToolPaletteGroup] = ToolPaletteGroup.toolbar

  @State private var groupFace: [String: Tool] = [
    "shapes": .rectangle,
    "callouts": .highlight,
    "cut": .redact,
  ]

  var body: some View {
    VStack(spacing: 0) {
      ZStack {
        AnnotationCanvasView(state: state)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        if state.showHelp {
          HelpOverlay(onDismiss: { state.toggleHelp() })
        }
      }
      statusBar
    }
    .frame(minWidth: AnnotatorChrome.minWidth, minHeight: AnnotatorChrome.contentMinHeight)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(state.stage.fill)
    .toolbar { toolbar }
    .overlay {
      if state.showSettings {
        Color.clear
          .contentShape(Rectangle())
          .onTapGesture { state.showSettings = false }
      }
    }
    .overlay(alignment: .topLeading) {
      if state.showSettings {
        StageSettingsPopover(state: state)
          .padding(.leading, 108)
          .padding(.top, 8)
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
    .onChange(of: state.tool) { _, tool in
      remember(tool)
    }
  }

  @ToolbarContentBuilder
  private var toolbar: some ToolbarContent {
    ToolbarItemGroup(placement: .navigation) {
      Button {
        state.toggleHelp()
      } label: {
        Image(systemName: state.showHelp ? "questionmark.circle.fill" : "questionmark.circle")
      }
      .help("Shortcuts (?)")

      Button {
        state.toggleSettings()
      } label: {
        Image(systemName: state.showSettings ? "gearshape.fill" : "gearshape")
      }
      .help("Stage (⌘,)")
    }

    if #available(macOS 26, *) {
      ToolbarSpacer(.fixed)
    }

    ToolbarItemGroup(placement: .automatic) {
      toolButton(.select, help: "Select (V)") {
        pick(.select)
      }

      ForEach(toolGroups) { group in
        toolSplit(group)
      }
    }

    if #available(macOS 26, *) {
      ToolbarSpacer(.flexible)
    }

    ToolbarItem(placement: .confirmationAction) {
      HStack(spacing: 10) {
        colorPalette
        NativeSaveButton(enabled: !state.isTyping) {
          state.saveAndQuit()
        }
        .fixedSize()
        .help("Copy to clipboard and close (S)")
      }
    }
  }

  private var statusBar: some View {
    HStack(spacing: 12) {
      Text(state.statusMessage)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .lineLimit(1)
      Spacer(minLength: 8)
      if state.zoom > 1.01 {
        Text("\(Int((state.zoom * 100).rounded()))%")
          .font(.system(size: 11).monospacedDigit())
          .foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 12)
    .frame(height: AnnotatorChrome.statusBarHeight)
    .background(Color(nsColor: .windowBackgroundColor))
    .overlay(alignment: .top) { Divider() }
  }

  private func remember(_ tool: Tool) {
    for group in toolGroups where group.tools.contains(tool) {
      groupFace[group.id] = tool
    }
  }

  private func pick(_ tool: Tool) {
    remember(tool)
    state.selectTool(tool)
  }

  private func face(for group: ToolPaletteGroup) -> Tool {
    if group.tools.contains(state.tool) { return state.tool }
    return groupFace[group.id] ?? group.tools[0]
  }

  private func toolButton(_ tool: Tool, help: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: tool.symbolName)
        .symbolRenderingMode(.palette)
        .foregroundStyle(state.tool == tool ? Color.accentColor : Color.primary)
        .frame(width: 16, height: 16)
        .padding(.horizontal, 4)
    }
    .help(help)
    .disabled(state.isTyping)
    .tint(state.tool == tool ? Color.accentColor : Color.primary)
    .accessibilityLabel(tool.label)
    .accessibilityAddTraits(state.tool == tool ? .isSelected : [])
  }

  private func toolSplit(_ group: ToolPaletteGroup) -> some View {
    let shown = face(for: group)
    let active = group.tools.contains(state.tool)
    return Menu {
      ForEach(group.tools) { tool in
        Button {
          pick(tool)
        } label: {
          Label(menuTitle(for: tool), systemImage: state.tool == tool ? "checkmark" : tool.symbolName)
        }
      }
    } label: {
      Image(systemName: shown.symbolName)
        .symbolRenderingMode(.palette)
        .foregroundStyle(active ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
    } primaryAction: {
      pick(shown)
    }
    .menuIndicator(.visible)
    .help("\(shown.label) (\(shown.hotkey.uppercased()))")
    .disabled(state.isTyping)
    .tint(active ? Color.accentColor : Color.primary)
    .accessibilityLabel("\(group.title), \(shown.label)")
  }

  private func menuTitle(for tool: Tool) -> String {
    "\(tool.label)  \(tool.hotkey.uppercased())"
  }

  private var colorPalette: some View {
    HStack(spacing: 3) {
      ForEach(AnnotationColor.allCases) { color in
        Button {
          state.setColor(color)
        } label: {
          ZStack {
            Circle()
              .strokeBorder(state.activeColor == color ? Color.primary : Color.clear, lineWidth: 1.5)
              .frame(width: 18, height: 18)
            Circle()
              .fill(color.swatch)
              .frame(width: 12, height: 12)
              .overlay(
                Circle().strokeBorder(Color.black.opacity(0.28), lineWidth: 0.5)
              )
          }
          .frame(width: 20, height: 22)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(color.rawValue.capitalized) (\(color.digitHotkey))")
        .accessibilityLabel("\(color.rawValue) color")
        .accessibilityAddTraits(state.activeColor == color ? .isSelected : [])
      }
    }
  }
}

private struct NativeSaveButton: NSViewRepresentable {
  let enabled: Bool
  let action: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(action: action)
  }

  func makeNSView(context: Context) -> NSButton {
    let button = NSButton(title: "Save", target: context.coordinator, action: #selector(Coordinator.press))
    button.bezelStyle = .rounded
    button.controlSize = .large
    button.bezelColor = .controlAccentColor
    button.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
    button.setContentHuggingPriority(.required, for: .horizontal)
    button.setContentCompressionResistancePriority(.required, for: .horizontal)
    return button
  }

  func updateNSView(_ button: NSButton, context: Context) {
    context.coordinator.action = action
    button.isEnabled = enabled
    button.bezelColor = .controlAccentColor
  }

  final class Coordinator: NSObject {
    var action: () -> Void
    init(action: @escaping () -> Void) { self.action = action }
    @objc func press() { action() }
  }
}
