import AppKit
import Foundation

final class ModifierFlagsMonitor {
  private let targetModifiers: ShortcutModifiers
  private let onKeyDown: @MainActor () -> Void
  private let onKeyUp: @MainActor () -> Void

  private var localToken: Any?
  private var globalToken: Any?
  private var isPressed = false

  init(
    targetModifiers: ShortcutModifiers,
    onKeyDown: @escaping @MainActor () -> Void,
    onKeyUp: @escaping @MainActor () -> Void
  ) {
    self.targetModifiers = targetModifiers
    self.onKeyDown = onKeyDown
    self.onKeyUp = onKeyUp
  }

  func activate() {
    guard localToken == nil, globalToken == nil else { return }

    localToken = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
      self?.handleFlagsChanged(event.modifierFlags)
      return event
    }
    globalToken = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
      self?.handleFlagsChanged(event.modifierFlags)
    }
  }

  func deactivate() {
    if let localToken {
      NSEvent.removeMonitor(localToken)
      self.localToken = nil
    }
    if let globalToken {
      NSEvent.removeMonitor(globalToken)
      self.globalToken = nil
    }

    if isPressed {
      isPressed = false
      Task { @MainActor in
        onKeyUp()
      }
    }
  }

  deinit {
    deactivate()
  }

  private func handleFlagsChanged(_ flags: NSEvent.ModifierFlags) {
    let currentModifiers = ShortcutModifiers(eventModifierFlags: flags)
    let shouldBePressed =
      !targetModifiers.isEmpty &&
      currentModifiers == targetModifiers

    guard shouldBePressed != isPressed else { return }
    isPressed = shouldBePressed

    Task { @MainActor in
      if shouldBePressed {
        onKeyDown()
      } else {
        onKeyUp()
      }
    }
  }
}
