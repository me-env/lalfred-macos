import Foundation
import AppKit

final class UnifiedShortcutMonitor {
  private let shortcutProvider: () -> Shortcut?
  private let onKeyDown: @MainActor () -> Void
  private let onKeyUp: (@MainActor () -> Void)?

  private var carbonMonitor: CarbonHotKeyMonitor?
  private var modifierMonitor: ModifierFlagsMonitor?

  init(
    shortcutProvider: @escaping () -> Shortcut?,
    onKeyDown: @escaping @MainActor () -> Void,
    onKeyUp: (@MainActor () -> Void)? = nil
  ) {
    self.shortcutProvider = shortcutProvider
    self.onKeyDown = onKeyDown
    self.onKeyUp = onKeyUp
  }

  deinit {
    deactivate()
  }

  func activate() {
    deactivate()
    guard let shortcut = shortcutProvider() else { return }

    if shortcut.isModifierOnly {
      let monitor = ModifierFlagsMonitor(
        targetModifiers: shortcut.modifiers,
        onKeyDown: onKeyDown,
        onKeyUp: onKeyUp ?? {}
      )
      modifierMonitor = monitor
      monitor.activate()
    } else {
      let monitor = CarbonHotKeyMonitor(
        shortcutProvider: { shortcut },
        onKeyDown: onKeyDown,
        onKeyUp: onKeyUp
      )
      carbonMonitor = monitor
      monitor.activate()
    }
  }

  func deactivate() {
    carbonMonitor?.deactivate()
    carbonMonitor = nil
    modifierMonitor?.deactivate()
    modifierMonitor = nil
  }
}
