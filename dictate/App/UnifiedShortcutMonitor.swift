import AppKit
import Foundation
import Observation

final class UnifiedShortcutMonitor {
  private let store: ShortcutStore
  private let onKeyDown: @MainActor () -> Void
  private let onKeyUp: (@MainActor () -> Void)?

  private var carbonMonitor: CarbonHotKeyMonitor?
  private var modifierMonitor: ModifierFlagsMonitor?
  private var isActive = false
  private var observationGeneration = 0

  init(
    store: ShortcutStore,
    onKeyDown: @escaping @MainActor () -> Void,
    onKeyUp: (@MainActor () -> Void)? = nil
  ) {
    self.store = store
    self.onKeyDown = onKeyDown
    self.onKeyUp = onKeyUp
  }

  deinit {
    carbonMonitor?.deactivate()
    modifierMonitor?.deactivate()
  }

  func activate() {
    guard !isActive else { return }
    isActive = true
    reload()
    observeStore()
  }

  func deactivate() {
    isActive = false
    deactivateInnerMonitors()
  }

  private func deactivateInnerMonitors() {
    carbonMonitor?.deactivate()
    carbonMonitor = nil
    modifierMonitor?.deactivate()
    modifierMonitor = nil
  }

  private func reload() {
    deactivateInnerMonitors()
    guard isActive, let shortcut = store.shortcut else { return }

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

  // `withObservationTracking` is one-shot; we re-register on each fire.
  // The generation counter ensures only the most recent registration
  // re-arms, so deactivate/activate cycles don't grow stale trackings.
  private func observeStore() {
    observationGeneration += 1
    let generation = observationGeneration
    withObservationTracking {
      _ = store.shortcut
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        guard let self else { return }
        guard self.observationGeneration == generation else { return }
        guard self.isActive else { return }
        self.reload()
        self.observeStore()
      }
    }
  }
}
