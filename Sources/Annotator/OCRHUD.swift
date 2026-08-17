import AppKit
import Combine
import SwiftUI

private final class ClearHostingView<Content: View>: NSHostingView<Content> {
  override var isOpaque: Bool { false }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
  }
}

@MainActor
final class OCRHUDController: ObservableObject {
  @Published var phase: Phase = .loading

  enum Phase: Equatable {
    case loading
    case success
    case failure
  }

  private var panel: NSPanel?

  func present() {
    let host = ClearHostingView(rootView: OCRLoadingHUD(model: self))
    host.frame = NSRect(origin: .zero, size: OCRLoadingHUD.windowSize)

    let panel = NSPanel(
      contentRect: host.frame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    panel.isFloatingPanel = true
    panel.becomesKeyOnlyIfNeeded = true
    panel.hidesOnDeactivate = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.level = .statusBar
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    panel.ignoresMouseEvents = true
    panel.isReleasedWhenClosed = false
    panel.appearance = NSAppearance(named: .darkAqua)
    panel.animationBehavior = .none
    panel.contentView = host

    Self.center(panel, on: Self.screenUnderMouse(), size: OCRLoadingHUD.windowSize)

    panel.alphaValue = 1
    panel.orderFrontRegardless()
    panel.displayIfNeeded()
    host.displayIfNeeded()
    self.panel = panel
  }

  func flushAppearance() {
    panel?.displayIfNeeded()
    panel?.contentView?.displayIfNeeded()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.09))
  }

  func finishSuccess() {
    withAnimation(OCRLoadingHUD.morph) {
      phase = .success
    }
  }

  func finishFailure() {
    withAnimation(OCRLoadingHUD.morph) {
      phase = .failure
    }
  }

  func dismiss() {
    guard let panel else { return }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.16
      context.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 1, 1)
      panel.animator().alphaValue = 0
    }
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.18))
    panel.orderOut(nil)
    panel.close()
    self.panel = nil
  }

  private static func center(_ panel: NSPanel, on screen: NSScreen, size: NSSize) {
    let visible = screen.visibleFrame
    panel.setFrameOrigin(NSPoint(
      x: visible.midX - size.width / 2,
      y: visible.minY + 48
    ))
  }

  private static func screenUnderMouse() -> NSScreen {
    let mouse = NSEvent.mouseLocation
    return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
      ?? NSScreen.main
      ?? NSScreen.screens[0]
  }
}

struct OCRLoadingHUD: View {
  @ObservedObject var model: OCRHUDController
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  static let windowSize = NSSize(width: 260, height: 88)
  static let morph = Animation.timingCurve(0.77, 0, 0.175, 1, duration: 0.32)

  var body: some View {
    chip
      .padding(20)
      .frame(width: Self.windowSize.width, height: Self.windowSize.height, alignment: .center)
      .environment(\.colorScheme, .dark)
      .animation(reduceMotion ? .easeOut(duration: 0.12) : Self.morph, value: model.phase)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(title(for: model.phase))
  }

  private var chip: some View {
    HStack(spacing: 10) {
      iconStack
      labelStack
    }
    .padding(.leading, 12)
    .padding(.trailing, 14)
    .padding(.vertical, 10)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color(red: 0.18, green: 0.18, blue: 0.19).opacity(0.94))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
    )
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .shadow(color: Color.black.opacity(0.38), radius: 14, y: 6)
    .fixedSize()
  }

  private var iconStack: some View {
    ZStack {
      spinner
        .hudLayer(visible: model.phase == .loading, blur: blurRadius)
      check
        .hudLayer(visible: model.phase == .success, blur: blurRadius)
      fail
        .hudLayer(visible: model.phase == .failure, blur: blurRadius)
    }
    .frame(width: 20, height: 20)
  }

  private var labelStack: some View {
    Text(title(for: model.phase))
      .hudLabel()
      .opacity(0)
      .overlay(alignment: .leading) {
        ZStack(alignment: .leading) {
          Text("Reading text")
            .hudLabel()
            .hudLayer(visible: model.phase == .loading, blur: blurRadius)
          Text("Copied")
            .hudLabel()
            .hudLayer(visible: model.phase == .success, blur: blurRadius)
          Text("No text found")
            .hudLabel()
            .hudLayer(visible: model.phase == .failure, blur: blurRadius)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
  }

  private var blurRadius: CGFloat {
    reduceMotion ? 0 : 9
  }

  private var spinner: some View {
    ProgressView()
      .progressViewStyle(.circular)
      .controlSize(.small)
      .tint(.white)
      .scaleEffect(0.9)
  }

  private var check: some View {
    Image(systemName: "checkmark.circle.fill")
      .font(.system(size: 18, weight: .semibold))
      .foregroundStyle(Color(red: 0.30, green: 0.82, blue: 0.47))
      .symbolRenderingMode(.hierarchical)
  }

  private var fail: some View {
    Image(systemName: "xmark.circle.fill")
      .font(.system(size: 18, weight: .semibold))
      .foregroundStyle(Color(red: 0.93, green: 0.38, blue: 0.37))
      .symbolRenderingMode(.hierarchical)
  }

  private func title(for phase: OCRHUDController.Phase) -> String {
    switch phase {
    case .loading: return "Reading text"
    case .success: return "Copied"
    case .failure: return "No text found"
    }
  }
}

private extension View {
  func hudLabel() -> some View {
    font(.system(size: 13, weight: .medium))
      .foregroundStyle(Color.white.opacity(0.96))
      .lineLimit(1)
      .fixedSize()
  }

  func hudLayer(visible: Bool, blur: CGFloat) -> some View {
    compositingGroup()
      .blur(radius: visible ? 0 : blur)
      .opacity(visible ? 1 : 0)
  }
}
