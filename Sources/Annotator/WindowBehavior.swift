import AppKit

/// Legal `NSWindow.CollectionBehavior` sets.
///
/// AppKit raises NSInternalInconsistencyException from `_validateCollectionBehavior:`
/// when these pairs are combined:
/// `canJoinAllSpaces` with `moveToActiveSpace`,
/// `managed` with `transient` or `stationary`,
/// `participatesInCycle` with `ignoresCycle`,
/// more than one of `fullScreenPrimary` / `fullScreenAuxiliary` / `fullScreenNone`,
/// `fullScreenAllowsTiling` with `fullScreenDisallowsTiling`.
enum WindowBehavior {
  /// Visible on every Space, including over full screen. Not `moveToActiveSpace`.
  static let allSpaces: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

  /// A non-interactive HUD. `stationary` is the opposite of `managed`, not of `canJoinAllSpaces`.
  static let stationaryHUD: NSWindow.CollectionBehavior = [
    .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
  ]
}
