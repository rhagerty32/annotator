import AppKit
import Foundation
import Sparkle

/// Sparkle check. The installed app carries SUPublicEDKey and relaunches after Install and Relaunch.
final class UpdateController: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate, NSMenuItemValidation {
  static let shared = UpdateController()

  private var controller: SPUStandardUpdaterController?
  private let feedOverrideKey = "AnnotatorUpdateFeedURL"

  static var isBundledApp: Bool {
    Bundle.main.bundleURL.pathExtension == "app"
  }

  static var hasPublicKey: Bool {
    guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String else {
      return false
    }
    return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  static var versionLabel: String {
    let short = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let build = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
    switch (short, build) {
    case let (s?, b?) where !s.isEmpty && s == b:
      return s
    case let (s?, b?) where !s.isEmpty && !b.isEmpty:
      return "\(s) (\(b))"
    case let (s?, _) where !s.isEmpty:
      return s
    default:
      return "Development build"
    }
  }

  static var statusDetail: String {
    if !isBundledApp {
      return "Install Annotator.app to download updates. This command line build cannot replace itself."
    }
    if !hasPublicKey {
      return "Downloads the latest release and relaunches Annotator once this copy includes its Sparkle public key."
    }
    return "Downloads the latest release and relaunches Annotator."
  }

  func startAutomaticChecks() {
    _ = makeController()
  }

  func checkFromUser() {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    guard let controller = makeController() else {
      explainUnavailable()
      NSApp.setActivationPolicy(.accessory)
      return
    }
    controller.checkForUpdates(nil)
  }

  @objc func checkForUpdatesMenu(_ sender: Any?) {
    checkFromUser()
  }

  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    guard menuItem.action == #selector(checkForUpdatesMenu(_:)) else { return true }
    guard let controller else { return true }
    return controller.updater.canCheckForUpdates
  }

  func feedURLString(for updater: SPUUpdater) -> String? {
    guard let override = UserDefaults.standard.string(forKey: feedOverrideKey) else { return nil }
    let trimmed = override.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  func standardUserDriverWillShowModalAlert() {
    revealUpdateUI()
  }

  func standardUserDriverWillHandleShowingUpdate(
    _ handleShowingUpdate: Bool,
    forUpdate update: SUAppcastItem,
    state: SPUUserUpdateState
  ) {
    revealUpdateUI()
  }

  func standardUserDriverWillFinishUpdateSession() {
    NSApp.setActivationPolicy(.accessory)
  }

  private func revealUpdateUI() {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
  }

  private func makeController() -> SPUStandardUpdaterController? {
    guard Self.isBundledApp, Self.hasPublicKey else { return nil }
    if let controller { return controller }
    let created = SPUStandardUpdaterController(
      startingUpdater: true,
      updaterDelegate: self,
      userDriverDelegate: self
    )
    controller = created
    return created
  }

  private func explainUnavailable() {
    let alert = NSAlert()
    if Self.isBundledApp {
      alert.messageText = "Check for Updates"
      alert.informativeText = Self.statusDetail
    } else {
      alert.messageText = "Open Annotator from Applications"
      alert.informativeText = "Check for Updates downloads the latest release and relaunches that copy."
    }
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }
}
