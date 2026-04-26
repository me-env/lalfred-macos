//
//  Shortcut.swift
//  dictate
//
//  Created by Cyprien Ricque on 4/26/26.
//

import Foundation

struct Shortcut: Codable, Hashable {
    var keyCode: UInt16
    var modifiers: ShortcutModifiers
}

struct ShortcutModifiers: OptionSet, Codable, Hashable {
    let rawValue: UInt8

    static let command = Self(rawValue: 1 << 0)
    static let option = Self(rawValue: 1 << 1)
    static let control = Self(rawValue: 1 << 2)
    static let shift = Self(rawValue: 1 << 3)
}
