import AppKit
import CoreGraphics
import SwiftUI

/// Screen Recording is tied to the ad-hoc signature, so an update leaves the
/// old switch on and the new build without access. This helper walks through
/// replacing that entry. It does not ask macOS to show its own prompt.
enum ScreenRecordingPrompt {
  enum Reason {
    case launch
    case capture
  }

  static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

  static var storageDirectory = AnnotatorFiles.supportDirectory

  static var currentVersion: String {
    let short = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if let short, !short.isEmpty { return short }
    return "dev"
  }

  static func hasAccess() -> Bool {
    CGPreflightScreenCaptureAccess()
  }

  /// Launch stays quiet after Remind me later until a capture is attempted
  /// or the app version changes. A capture attempt always offers the helper
  /// again while access is missing.
  static func shouldShow(reason: Reason, hasAccess: Bool, snoozedVersion: String?, currentVersion: String) -> Bool {
    if hasAccess { return false }
    switch reason {
    case .launch:
      return snoozedVersion != currentVersion
    case .capture:
      return true
    }
  }

  static func shouldShow(reason: Reason) -> Bool {
    shouldShow(
      reason: reason,
      hasAccess: hasAccess(),
      snoozedVersion: readSnooze(),
      currentVersion: currentVersion
    )
  }

  static func snooze() {
    let url = storageDirectory.appendingPathComponent("screen-recording-snooze")
    try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
    try? Data(currentVersion.utf8).write(to: url, options: .atomic)
  }

  static func readSnooze() -> String? {
    let url = storageDirectory.appendingPathComponent("screen-recording-snooze")
    guard let data = try? Data(contentsOf: url),
          let text = String(data: data, encoding: .utf8)
    else { return nil }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  static var appIcon: NSImage {
    if let icon = NSApp.applicationIconImage, icon.size.width > 1, icon.size.height > 1 {
      return icon
    }
    return NSImage(size: NSSize(width: 56, height: 56))
  }
}

enum ScreenRecordingPhase: Equatable {
  case initial
  case waiting
  case success
}

@MainActor
final class ScreenRecordingHelperModel: NSObject, ObservableObject {
  @Published var phase: ScreenRecordingPhase
  let polls: Bool
  private var timer: Timer?
  private(set) var isPolling = false

  init(phase: ScreenRecordingPhase = .initial, polls: Bool = true) {
    self.phase = phase
    self.polls = polls
    super.init()
  }

  func startPolling() {
    guard polls, timer == nil else { return }
    poll()
    let timer = Timer(timeInterval: 1, target: self, selector: #selector(pollTimer), userInfo: nil, repeats: true)
    RunLoop.main.add(timer, forMode: .default)
    self.timer = timer
    isPolling = true
  }

  @objc nonisolated private func pollTimer() {
    Task { @MainActor in
      poll()
    }
  }

  func stopPolling() {
    timer?.invalidate()
    timer = nil
    isPolling = false
  }

  func openSettings() {
    if phase != .success {
      phase = .waiting
    }
    NSWorkspace.shared.open(ScreenRecordingPrompt.settingsURL)
    ScreenRecordingHelper.orderFront()
  }

  func remindLater() {
    ScreenRecordingPrompt.snooze()
    ScreenRecordingHelper.close()
  }

  func restart() {
    ScreenRecordingHelper.relaunch()
  }

  private func poll() {
    guard phase != .success else { return }
    if ScreenRecordingPrompt.hasAccess() {
      phase = .success
    }
  }
}

@MainActor
enum ScreenRecordingHelper {
  private static var controller: Controller?
  static var onDismiss: (() -> Void)?

  static var isOpen: Bool {
    controller?.window?.isVisible == true
  }

  static func show(reason: ScreenRecordingPrompt.Reason) {
    guard ScreenRecordingPrompt.shouldShow(reason: reason) else { return }
    present(model: ScreenRecordingHelperModel())
  }

  static func orderFront() {
    guard let window = controller?.window else { return }
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  static func close() {
    controller?.close()
  }

  static func relaunch() {
    let target = BundleExecutable.applicationURL
    AgentBridge.stop()
    guard let target else {
      relaunchCurrentExecutable()
      return
    }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.createsNewApplicationInstance = true
    NSWorkspace.shared.openApplication(at: target, configuration: configuration) { _, error in
      if let error {
        fputs("Annotator: could not restart: \(error.localizedDescription)\n", stderr)
        return
      }
      NSApp.terminate(nil)
    }
  }

  static func runSelfTest(directory: URL) -> Int32 {
    if ScreenRecordingPrompt.shouldShow(reason: .launch, hasAccess: true, snoozedVersion: nil, currentVersion: "1") {
      fputs("screen recording self-test: granted access still offers the helper\n", stderr)
      return 1
    }
    if ScreenRecordingPrompt.shouldShow(reason: .launch, hasAccess: false, snoozedVersion: "1.1.0", currentVersion: "1.1.0") {
      fputs("screen recording self-test: snooze did not hide the launch prompt\n", stderr)
      return 1
    }
    if !ScreenRecordingPrompt.shouldShow(reason: .launch, hasAccess: false, snoozedVersion: "1.1.0", currentVersion: "1.2.0") {
      fputs("screen recording self-test: a new version stayed snoozed\n", stderr)
      return 1
    }
    if !ScreenRecordingPrompt.shouldShow(reason: .capture, hasAccess: false, snoozedVersion: "1.1.0", currentVersion: "1.1.0") {
      fputs("screen recording self-test: snooze hid a capture attempt\n", stderr)
      return 1
    }
    if ScreenRecordingPrompt.shouldShow(reason: .capture, hasAccess: true, snoozedVersion: nil, currentVersion: "1") {
      fputs("screen recording self-test: capture offered the helper when access is granted\n", stderr)
      return 1
    }

    let saved = ScreenRecordingPrompt.storageDirectory
    let temp = directory.appendingPathComponent("snooze-store", isDirectory: true)
    ScreenRecordingPrompt.storageDirectory = temp
    defer { ScreenRecordingPrompt.storageDirectory = saved }
    try? FileManager.default.removeItem(at: temp)
    ScreenRecordingPrompt.snooze()
    if ScreenRecordingPrompt.readSnooze() != ScreenRecordingPrompt.currentVersion {
      fputs("screen recording self-test: snooze file did not store the version\n", stderr)
      return 1
    }

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let box = ScreenRecordingTestBox()
    DispatchQueue.main.async {
      box.code = MainActor.assumeIsolated {
        renderSelfTest(directory: directory)
      }
      app.stop(nil)
      if let event = NSEvent.otherEvent(
        with: .applicationDefined,
        location: .zero,
        modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: 0,
        context: nil,
        subtype: 0,
        data1: 0,
        data2: 0
      ) {
        app.postEvent(event, atStart: true)
      }
    }
    app.run()
    return box.code
  }

  private static func renderSelfTest(directory: URL) -> Int32 {
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try writeSnapshot(.initial, scheme: .light, to: directory.appendingPathComponent("initial-light.png"))
      try writeSnapshot(.initial, scheme: .dark, to: directory.appendingPathComponent("initial-dark.png"))
      try writeSnapshot(.waiting, scheme: .light, to: directory.appendingPathComponent("waiting.png"))
      try writeSnapshot(.success, scheme: .light, to: directory.appendingPathComponent("success.png"))
    } catch {
      fputs("screen recording self-test: \(error.localizedDescription)\n", stderr)
      return 1
    }

    let model = ScreenRecordingHelperModel()
    present(model: model)
    guard let window = controller?.window, window.title == "Screen Recording", window.isVisible else {
      fputs("screen recording self-test: window did not open\n", stderr)
      return 1
    }
    if !model.isPolling {
      fputs("screen recording self-test: permission poll did not start\n", stderr)
      return 1
    }
    window.displayIfNeeded()
    window.contentView?.layoutSubtreeIfNeeded()
    RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.2))
    let shown = collectedStrings(in: window.contentView)
    for phrase in ["One quick update", "Open Screen Recording Settings", "Remind me later", "Remove the old Annotator"] {
      if !shown.contains(where: { $0.contains(phrase) }) {
        fputs("screen recording self-test: missing \(phrase)\n\(shown.joined(separator: "\n"))\n", stderr)
        return 1
      }
    }
    if let rep = bitmap(of: window.contentView) {
      let url = directory.appendingPathComponent("window-light.png")
      if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: url)
      }
    }
    close()
    if model.isPolling {
      fputs("screen recording self-test: permission poll did not stop\n", stderr)
      return 1
    }
    fputs("screen recording self-test: ok\n", stderr)
    return 0
  }

  private static func writeSnapshot(_ phase: ScreenRecordingPhase, scheme: ColorScheme, to url: URL) throws {
    let model = ScreenRecordingHelperModel(phase: phase, polls: false)
    let host = NSHostingView(rootView: ScreenRecordingHelperView(model: model, forcedScheme: scheme))
    host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
    host.frame = NSRect(x: 0, y: 0, width: 560, height: 40)
    let window = NSWindow(
      contentRect: host.frame,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    window.contentView = host
    window.layoutIfNeeded()
    host.layoutSubtreeIfNeeded()
    var height = host.fittingSize.height
    if height < 200 { height = phase == .success ? 360 : 760 }
    host.frame = NSRect(x: 0, y: 0, width: 560, height: height)
    window.setContentSize(NSSize(width: 560, height: height))
    window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
    window.orderFrontRegardless()
    window.displayIfNeeded()
    host.layoutSubtreeIfNeeded()
    guard let rep = bitmap(of: host) else {
      throw NSError(domain: "Annotator", code: 1, userInfo: [NSLocalizedDescriptionKey: "could not draw \(url.lastPathComponent)"])
    }
    guard let data = rep.representation(using: .png, properties: [:]) else {
      throw NSError(domain: "Annotator", code: 1, userInfo: [NSLocalizedDescriptionKey: "could not encode \(url.lastPathComponent)"])
    }
    try data.write(to: url, options: .atomic)
    window.orderOut(nil)
  }

  private static func bitmap(of view: NSView?) -> NSBitmapImageRep? {
    guard let view else { return nil }
    let bounds = view.bounds
    guard bounds.width > 1, bounds.height > 1 else { return nil }
    let scale = view.window?.backingScaleFactor ?? 2
    guard let rep = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: Int(bounds.width * scale),
      pixelsHigh: Int(bounds.height * scale),
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    ) else { return nil }
    rep.size = bounds.size
    view.cacheDisplay(in: bounds, to: rep)
    return rep
  }

  private static func collectedStrings(in view: NSView?) -> [String] {
    guard let view else { return [] }
    var values: [String] = []
    if let text = view as? NSTextField {
      values.append(text.stringValue)
    }
    if let button = view as? NSButton {
      values.append(button.title)
    }
    if let label = view.accessibilityLabel() {
      values.append(label)
    }
    if let value = view.accessibilityValue() as? String {
      values.append(value)
    }
    for subview in view.subviews {
      values.append(contentsOf: collectedStrings(in: subview))
    }
    return values
  }

  private static func present(model: ScreenRecordingHelperModel) {
    if let controller, controller.window?.isVisible == true {
      controller.model = model
      controller.window?.contentView = NSHostingView(rootView: ScreenRecordingHelperView(model: model))
      orderFront()
      model.startPolling()
      return
    }
    let controller = Controller(model: model)
    self.controller = controller
    controller.showWindow(nil)
    model.startPolling()
    orderFront()
  }

  private static func relaunchCurrentExecutable() {
    let process = Process()
    process.executableURL = BundleExecutable.currentURL
    process.arguments = []
    do {
      try process.run()
      NSApp.terminate(nil)
    } catch {
      fputs("Annotator: could not restart: \(error.localizedDescription)\n", stderr)
    }
  }

  private final class Controller: NSWindowController, NSWindowDelegate {
    var model: ScreenRecordingHelperModel

    init(model: ScreenRecordingHelperModel) {
      self.model = model
      let host = NSHostingView(rootView: ScreenRecordingHelperView(model: model))
      host.sizingOptions = [.minSize, .intrinsicContentSize]
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 560, height: 760),
        styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
        backing: .buffered,
        defer: false
      )
      window.contentView = host
      window.title = "Screen Recording"
      window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
      window.titleVisibility = .hidden
      window.titlebarAppearsTransparent = true
      window.titlebarSeparatorStyle = .none
      window.isMovableByWindowBackground = true
      window.isReleasedWhenClosed = false
      window.level = .floating
      window.hidesOnDeactivate = false
      window.animationBehavior = .none
      window.backgroundColor = .windowBackgroundColor
      let problem = AnnotatorCatchException {
        window.collectionBehavior = WindowBehavior.allSpaces
      }
      if let problem {
        fputs("Annotator: could not configure Screen Recording window: \(problem.reason ?? problem.name.rawValue)\n", stderr)
      }
      super.init(window: window)
      window.delegate = self
      host.layoutSubtreeIfNeeded()
      let fitted = host.fittingSize
      let height = fitted.height > 200 ? fitted.height : 760
      window.setContentSize(NSSize(width: 560, height: height))
      window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    func windowWillClose(_ notification: Notification) {
      model.stopPolling()
      ScreenRecordingHelper.onDismiss?()
      ScreenRecordingHelper.onDismiss = nil
      ScreenRecordingHelper.controller = nil
    }
  }
}

private final class ScreenRecordingTestBox: @unchecked Sendable {
  var code: Int32 = 1
}

struct ScreenRecordingHelperView: View {
  @ObservedObject var model: ScreenRecordingHelperModel
  var forcedScheme: ColorScheme?
  @Environment(\.colorScheme) private var environmentScheme
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var scheme: ColorScheme { forcedScheme ?? environmentScheme }
  private var palette: ScreenRecordingPalette { ScreenRecordingPalette(scheme: scheme) }

  var body: some View {
    VStack(spacing: 0) {
      titleBar
      if model.phase == .success {
        successBody
      } else {
        guideBody
      }
    }
    .frame(width: 560)
    .background(palette.surface)
    .onChange(of: model.phase) { _, phase in
      let message: String
      switch phase {
      case .initial:
        return
      case .waiting:
        message = "Waiting for permission..."
      case .success:
        message = "Permission granted"
      }
      AccessibilityNotification.Announcement(message).post()
    }
  }

  private var titleBar: some View {
    ZStack {
      Text("Screen Recording")
        .font(screenFont(13, weight: .semibold))
        .tracking(-0.13)
        .foregroundStyle(palette.text)
        .accessibilityAddTraits(.isHeader)
    }
    .frame(maxWidth: .infinity)
    .frame(height: 52)
    .background(palette.titlebar)
    .overlay(alignment: .bottom) {
      Rectangle().fill(palette.hairline).frame(height: 0.5)
    }
  }

  private var guideBody: some View {
    VStack(alignment: .leading, spacing: 0) {
      hero
      VStack(alignment: .leading, spacing: 20) {
        stepOne
        stepTwo
        stepThree
      }
      if model.phase == .waiting {
        statusRow(
          text: "Waiting for permission...",
          tint: palette.secondary,
          symbol: nil,
          spinning: true
        )
        .padding(.top, 8)
        .accessibilityLabel("Waiting for permission...")
      }
      Button(action: model.remindLater) {
        Text("Remind me later")
          .font(screenFont(13, weight: .medium))
          .tracking(-0.13)
          .foregroundStyle(palette.blue)
          .padding(.horizontal, 14)
          .padding(.vertical, 10)
      }
      .buttonStyle(.plain)
      .frame(maxWidth: .infinity)
      .padding(.top, 8)
      .accessibilityLabel("Remind me later")
    }
    .padding(.horizontal, 32)
    .padding(.top, 24)
    .padding(.bottom, 16)
  }

  private var hero: some View {
    HStack(alignment: .top, spacing: 16) {
      appIcon(size: 56, radius: 12)
        .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
        .overlay(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
        )
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 6) {
        Text("One quick update")
          .font(screenFont(20, weight: .bold))
          .tracking(-0.44)
          .foregroundStyle(palette.text)
        Text("Annotator needs permission to see your screen again after the update.")
          .font(screenFont(15, weight: .regular))
          .tracking(-0.15)
          .foregroundStyle(palette.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(.bottom, 24)
    .accessibilityElement(children: .combine)
  }

  private var stepOne: some View {
    step(number: "1", role: model.phase == .waiting ? .done : .active) {
      Text("Open Screen Recording settings")
        .font(screenFont(16, weight: .semibold))
        .tracking(-0.24)
        .foregroundStyle(palette.text)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 10)
      if model.phase == .waiting {
        Button(action: model.openSettings) {
          Text("Open Settings again")
            .font(screenFont(15, weight: .semibold))
            .tracking(-0.15)
            .foregroundStyle(palette.blue)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
              RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(palette.blue.opacity(scheme == .dark ? 0.45 : 0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Settings again")
      } else {
        Button(action: model.openSettings) {
          Text("Open Screen Recording Settings")
            .font(screenFont(15, weight: .semibold))
            .tracking(-0.15)
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
              RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.blue)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open Screen Recording Settings")
      }
    }
  }

  private var stepTwo: some View {
    step(number: "2", role: model.phase == .waiting ? .active : .neutral) {
      Text("In the list, click Annotator, then click the minus button.")
        .font(screenFont(16, weight: .semibold))
        .tracking(-0.24)
        .foregroundStyle(palette.text)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.bottom, 10)
      illustration {
        settingsList {
          settingsRow(name: "Chrome", icon: .placeholder, selected: false, dimmed: true, toggle: .on)
          settingsRow(name: "Annotator.app", icon: .app, selected: true, dimmed: false, toggle: .on)
          settingsRow(name: "Zoom", icon: .blue, selected: false, dimmed: true, toggle: .off)
        }
        HStack(spacing: 8) {
          hitButton(symbol: "−", filled: false, ring: true, arrow: .down)
          hitButton(symbol: "+", filled: false, ring: false, arrow: .none)
          Text("Remove the old Annotator")
            .font(screenFont(12, weight: .regular))
            .tracking(-0.12)
            .foregroundStyle(palette.secondary)
          Spacer(minLength: 0)
        }
        .padding(.top, 10)
      }
    }
  }

  private var stepThree: some View {
    step(number: "3", role: .neutral) {
      Text("Click the plus button, pick Annotator from Applications, then turn its switch on.")
        .font(screenFont(16, weight: .semibold))
        .tracking(-0.24)
        .foregroundStyle(palette.text)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.bottom, 10)
      illustration {
        settingsList {
          HStack(spacing: 10) {
            rowIcon(.app)
            Text("Annotator")
              .font(screenFont(13, weight: .medium))
              .tracking(-0.13)
              .foregroundStyle(palette.text)
            Spacer(minLength: 0)
            ZStack {
              toggleGlyph(.mid)
              RoundedRectangle(cornerRadius: 999, style: .continuous)
                .stroke(palette.blue, lineWidth: 2)
                .padding(-6)
                .allowsHitTesting(false)
            }
            .overlay(alignment: .trailing) {
              hitArrow(direction: .left)
                .offset(x: 26)
            }
            .padding(.trailing, 18)
          }
          .padding(.horizontal, 10)
          .frame(minHeight: 38)
        }
        HStack(spacing: 8) {
          hitButton(symbol: "−", filled: false, ring: false, arrow: .none)
          hitButton(symbol: "+", filled: true, ring: true, arrow: .none)
          Text("Add Annotator again")
            .font(screenFont(12, weight: .regular))
            .tracking(-0.12)
            .foregroundStyle(palette.secondary)
          Spacer(minLength: 0)
        }
        .padding(.top, 10)
      }
    }
  }

  private var successBody: some View {
    VStack(spacing: 0) {
      ZStack {
        Circle().fill(palette.green.opacity(scheme == .dark ? 0.16 : 0.12))
          .frame(width: 72, height: 72)
        Circle().fill(palette.green)
          .frame(width: 40, height: 40)
        Image(systemName: "checkmark")
          .font(.system(size: 18, weight: .bold))
          .foregroundStyle(Color.white)
      }
      .padding(.bottom, 20)
      .accessibilityHidden(true)
      Text("All set")
        .font(screenFont(22, weight: .bold))
        .tracking(-0.48)
        .foregroundStyle(palette.text)
        .padding(.bottom, 8)
      Text("Annotator can see your screen again. Restart once so the change takes effect.")
        .font(screenFont(15, weight: .regular))
        .tracking(-0.15)
        .foregroundStyle(palette.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 360)
        .padding(.bottom, 28)
      Button(action: model.restart) {
        HStack(spacing: 8) {
          Image(systemName: "arrow.clockwise")
            .font(.system(size: 14, weight: .semibold))
          Text("Restart Annotator")
            .font(screenFont(15, weight: .semibold))
            .tracking(-0.15)
        }
        .foregroundStyle(Color.white)
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .background(
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(palette.green)
        )
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Restart Annotator")
      statusRow(text: "Permission granted", tint: palette.greenText, symbol: "checkmark", spinning: false)
        .padding(.top, 16)
        .accessibilityLabel("Permission granted")
    }
    .padding(.horizontal, 32)
    .padding(.top, 32)
    .padding(.bottom, 28)
    .frame(maxWidth: .infinity)
  }

  private func step<Content: View>(number: String, role: StepRole, @ViewBuilder content: () -> Content) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Text(number)
        .font(screenFont(13, weight: .bold))
        .foregroundStyle(role == .neutral ? palette.stepNeutralText : Color.white)
        .frame(width: 28, height: 28)
        .background(Circle().fill(role == .neutral ? palette.stepNeutral : palette.blue))
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 0) {
        content()
      }
    }
  }

  private func illustration<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      content()
    }
    .padding(.init(top: 10, leading: 12, bottom: 22, trailing: 12))
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(palette.fill)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(palette.illustrationBorder, lineWidth: 0.5)
    )
  }

  private func settingsList<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    VStack(spacing: 0) {
      content()
    }
    .background(
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(palette.listSurface)
    )
    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
  }

  private func settingsRow(name: String, icon: RowIcon, selected: Bool, dimmed: Bool, toggle: ToggleKind) -> some View {
    HStack(spacing: 10) {
      rowIcon(icon)
      Text(name)
        .font(screenFont(13, weight: selected ? .semibold : .medium))
        .tracking(-0.13)
        .foregroundStyle(palette.text)
      Spacer(minLength: 0)
      toggleGlyph(toggle)
    }
    .padding(.horizontal, 10)
    .frame(minHeight: 38)
    .frame(maxWidth: .infinity)
    .background(selected ? palette.select : Color.clear)
    .opacity(dimmed ? 0.42 : 1)
    .overlay(alignment: .top) {
      if name != "Chrome" && name != "Annotator" {
        Rectangle().fill(palette.rowHairline).frame(height: 0.5)
      }
    }
  }

  private func rowIcon(_ icon: RowIcon) -> some View {
    Group {
      switch icon {
      case .app:
        appIcon(size: 22, radius: 5)
      case .placeholder:
        RoundedRectangle(cornerRadius: 5, style: .continuous)
          .fill(LinearGradient(colors: palette.grayIcon, startPoint: .topLeading, endPoint: .bottomTrailing))
      case .blue:
        RoundedRectangle(cornerRadius: 5, style: .continuous)
          .fill(LinearGradient(colors: [Color(red: 0.35, green: 0.78, blue: 0.98), palette.blue], startPoint: .topLeading, endPoint: .bottomTrailing))
      }
    }
    .frame(width: 22, height: 22)
    .accessibilityHidden(true)
  }

  private func appIcon(size: CGFloat, radius: CGFloat) -> some View {
    Image(nsImage: ScreenRecordingPrompt.appIcon)
      .resizable()
      .interpolation(.high)
      .frame(width: size, height: size)
      .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
  }

  private func toggleGlyph(_ kind: ToggleKind) -> some View {
    ZStack(alignment: .leading) {
      Capsule().fill(kind.fill(palette, scheme: scheme))
        .frame(width: 34, height: 20)
      Circle()
        .fill(Color.white)
        .frame(width: 16, height: 16)
        .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
        .offset(x: kind.knob)
    }
    .frame(width: 34, height: 20)
    .accessibilityHidden(true)
  }

  private func hitButton(symbol: String, filled: Bool, ring: Bool, arrow: ArrowDirection) -> some View {
    ZStack {
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(filled ? palette.blue : palette.toolFill)
        .overlay(
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .stroke(filled ? Color.clear : palette.toolBorder, lineWidth: 0.5)
        )
      Text(symbol)
        .font(.system(size: 18, weight: .medium))
        .foregroundStyle(filled ? Color.white : palette.text)
        .offset(y: symbol == "+" ? -1 : 0)
      if ring {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .stroke(palette.blue, lineWidth: 2)
          .padding(-5)
          .allowsHitTesting(false)
      }
    }
    .frame(width: 32, height: 26)
    .overlay(alignment: .bottom) {
      if arrow == .down {
        hitArrow(direction: .down)
          .offset(y: 22)
      }
    }
    .accessibilityHidden(true)
  }

  private func hitArrow(direction: ArrowDirection) -> some View {
    Path { path in
      switch direction {
      case .down:
        path.move(to: CGPoint(x: 9, y: 2))
        path.addLine(to: CGPoint(x: 9, y: 13))
        path.move(to: CGPoint(x: 5.5, y: 9.5))
        path.addLine(to: CGPoint(x: 9, y: 13))
        path.addLine(to: CGPoint(x: 12.5, y: 9.5))
      case .left:
        path.move(to: CGPoint(x: 16, y: 9))
        path.addLine(to: CGPoint(x: 5, y: 9))
        path.move(to: CGPoint(x: 8.5, y: 5.5))
        path.addLine(to: CGPoint(x: 5, y: 9))
        path.addLine(to: CGPoint(x: 8.5, y: 12.5))
      case .none:
        break
      }
    }
    .stroke(palette.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    .frame(width: 18, height: 18)
    .accessibilityHidden(true)
  }

  private func statusRow(text: String, tint: Color, symbol: String?, spinning: Bool) -> some View {
    HStack(spacing: 8) {
      if spinning {
        if reduceMotion {
          Circle()
            .stroke(palette.secondary.opacity(0.45), lineWidth: 2)
            .frame(width: 14, height: 14)
        } else {
          ProgressView()
            .controlSize(.small)
        }
      } else if let symbol {
        Image(systemName: symbol)
          .font(.system(size: 11, weight: .bold))
          .foregroundStyle(tint)
      }
      Text(text)
        .font(screenFont(13, weight: spinning ? .medium : .semibold))
        .tracking(-0.13)
        .foregroundStyle(tint)
    }
    .frame(maxWidth: .infinity)
    .frame(minHeight: 22)
  }

  private func screenFont(_ size: CGFloat, weight: Font.Weight) -> Font {
    .system(size: size, weight: weight)
  }
}

private enum StepRole {
  case active
  case done
  case neutral
}

private enum RowIcon {
  case app
  case placeholder
  case blue
}

private enum ToggleKind {
  case on
  case off
  case mid

  var knob: CGFloat {
    switch self {
    case .on: return 16
    case .off: return 2
    case .mid: return 9
    }
  }

  func fill(_ palette: ScreenRecordingPalette, scheme: ColorScheme) -> Color {
    switch self {
    case .on:
      return palette.green
    case .off:
      return palette.toggleOff
    case .mid:
      return palette.green
    }
  }
}

private enum ArrowDirection {
  case down
  case left
  case none
}

private struct ScreenRecordingPalette {
  var scheme: ColorScheme

  var surface: Color { scheme == .dark ? Color(red: 0.173, green: 0.173, blue: 0.180) : .white }
  var titlebar: LinearGradient {
    scheme == .dark
      ? LinearGradient(colors: [Color(red: 0.227, green: 0.227, blue: 0.235), Color(red: 0.196, green: 0.196, blue: 0.204)], startPoint: .top, endPoint: .bottom)
      : LinearGradient(colors: [Color(red: 0.984, green: 0.984, blue: 0.988), Color(red: 0.949, green: 0.949, blue: 0.957)], startPoint: .top, endPoint: .bottom)
  }
  var text: Color { scheme == .dark ? Color(red: 0.961, green: 0.961, blue: 0.969) : Color(red: 0.114, green: 0.114, blue: 0.122) }
  var secondary: Color { scheme == .dark ? Color(red: 0.596, green: 0.596, blue: 0.616) : Color(red: 0.431, green: 0.431, blue: 0.451) }
  var fill: Color { scheme == .dark ? Color(red: 0.110, green: 0.110, blue: 0.118) : Color(red: 0.949, green: 0.949, blue: 0.969) }
  var listSurface: Color { scheme == .dark ? Color(red: 0.227, green: 0.227, blue: 0.235) : .white }
  var select: Color {
    scheme == .dark
      ? Color(red: 10 / 255, green: 132 / 255, blue: 1, opacity: 0.28)
      : Color(red: 0, green: 122 / 255, blue: 1, opacity: 0.14)
  }
  var hairline: Color { scheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.10) }
  var rowHairline: Color { scheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08) }
  var illustrationBorder: Color { scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06) }
  var blue: Color { scheme == .dark ? Color(red: 0.039, green: 0.518, blue: 1) : Color(red: 0, green: 0.478, blue: 1) }
  var stepNeutral: Color { scheme == .dark ? Color(red: 0.282, green: 0.282, blue: 0.290) : Color(red: 0.820, green: 0.820, blue: 0.839) }
  var stepNeutralText: Color { scheme == .dark ? Color(red: 0.961, green: 0.961, blue: 0.969) : Color(red: 0.114, green: 0.114, blue: 0.122) }
  var green: Color { Color(red: 0.204, green: 0.780, blue: 0.349) }
  var greenText: Color {
    scheme == .dark ? Color(red: 0.188, green: 0.820, blue: 0.345) : Color(red: 0.141, green: 0.541, blue: 0.239)
  }
  var toggleOff: Color { scheme == .dark ? Color(red: 0.388, green: 0.388, blue: 0.400) : Color(red: 0.898, green: 0.898, blue: 0.918) }
  var toolFill: Color { scheme == .dark ? Color(red: 0.282, green: 0.282, blue: 0.290) : .white }
  var toolBorder: Color { scheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.14) }
  var grayIcon: [Color] {
    scheme == .dark
      ? [Color(red: 0.388, green: 0.388, blue: 0.400), Color(red: 0.557, green: 0.557, blue: 0.576)]
      : [Color(red: 0.557, green: 0.557, blue: 0.576), Color(red: 0.682, green: 0.682, blue: 0.698)]
  }
}
