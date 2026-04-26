//
//  ShortcutModifiers+SwiftUI.swift
//  dictate
//
//  Created by Cyprien Ricque on 4/26/26.
//

import SwiftUI

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
}
