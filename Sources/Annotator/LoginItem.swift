import Foundation
import ServiceManagement

enum LoginItem {
  static var isBundledApp: Bool {
    Bundle.main.bundleURL.pathExtension == "app"
  }

  static var isEnabled: Bool {
    guard isBundledApp else { return false }
    return SMAppService.mainApp.status == .enabled
  }

  static var requiresApproval: Bool {
    guard isBundledApp else { return false }
    return SMAppService.mainApp.status == .requiresApproval
  }

  static func setEnabled(_ enabled: Bool) throws {
    if enabled {
      if SMAppService.mainApp.status != .enabled {
        try SMAppService.mainApp.register()
      }
    } else if SMAppService.mainApp.status != .notRegistered {
      try SMAppService.mainApp.unregister()
    }
  }

  static var detail: String {
    guard isBundledApp else {
      return "Install Annotator.app to open it when you sign in."
    }
    if requiresApproval {
      return "macOS is waiting for approval in System Settings, General, Login Items."
    }
    if isEnabled {
      return "Annotator opens when you sign in, so the shortcut is ready."
    }
    return "Opens the menu bar helper when you sign in."
  }
}
