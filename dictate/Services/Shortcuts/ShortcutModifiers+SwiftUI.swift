import SwiftUI
import AppKit

extension ShortcutModifiers {
  init(eventModifiers: SwiftUI.EventModifiers) {
    var shortcutModifiers: ShortcutModifiers = []
    
    if eventModifiers.contains(.command) {
      shortcutModifiers.insert(.command)
    }
    if eventModifiers.contains(.option) {
      shortcutModifiers.insert(.option)
    }
    if eventModifiers.contains(.control) {
      shortcutModifiers.insert(.control)
    }
    if eventModifiers.contains(.shift) {
      shortcutModifiers.insert(.shift)
    }
    
    self = shortcutModifiers
  }

  init(eventModifierFlags: NSEvent.ModifierFlags) {
    var shortcutModifiers: ShortcutModifiers = []
    let flags = eventModifierFlags.intersection(.deviceIndependentFlagsMask)

    if flags.contains(.command) {
      shortcutModifiers.insert(.command)
    }
    if flags.contains(.option) {
      shortcutModifiers.insert(.option)
    }
    if flags.contains(.control) {
      shortcutModifiers.insert(.control)
    }
    if flags.contains(.shift) {
      shortcutModifiers.insert(.shift)
    }

    self = shortcutModifiers
  }
}
