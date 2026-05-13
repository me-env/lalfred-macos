import Foundation

struct Shortcut: Codable, Hashable, Sendable {
  static let modifierOnlyKeyCode = UInt16.max

  var keyCode: UInt16
  var modifiers: ShortcutModifiers

  var isModifierOnly: Bool {
    keyCode == Self.modifierOnlyKeyCode && !modifiers.isEmpty
  }
  
  var labels: [String] {
    var tokens: [String] = []
    
    if self.modifiers.contains(.control) {
      tokens.append("⌃")
    }
    if self.modifiers.contains(.option) {
      tokens.append("⌥")
    }
    if self.modifiers.contains(.shift) {
      tokens.append("⇧")
    }
    if self.modifiers.contains(.command) {
      tokens.append("⌘")
    }
    
    if !isModifierOnly {
      tokens.append(KeyCode.displayLabel(for: self.keyCode))
    }
    return tokens
  }
}

struct ShortcutModifiers: OptionSet, Codable, Hashable {
  let rawValue: UInt8
  
  static let command = Self(rawValue: 1 << 0)
  static let option = Self(rawValue: 1 << 1)
  static let control = Self(rawValue: 1 << 2)
  static let shift = Self(rawValue: 1 << 3)

  var count: Int {
    rawValue.nonzeroBitCount
  }
}
