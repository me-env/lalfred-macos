//
//  KeyCode.swift
//  dictate
//
//  Created by Cyprien Ricque on 4/26/26.
//

import Foundation
import Carbon.HIToolbox

public enum KeyCode {
  public static func from(character: Character) -> UInt16? {
    switch character.lowercased() {
    case "a": return UInt16(kVK_ANSI_A)
    case "b": return UInt16(kVK_ANSI_B)
    case "c": return UInt16(kVK_ANSI_C)
    case "d": return UInt16(kVK_ANSI_D)
    case "e": return UInt16(kVK_ANSI_E)
    case "f": return UInt16(kVK_ANSI_F)
    case "g": return UInt16(kVK_ANSI_G)
    case "h": return UInt16(kVK_ANSI_H)
    case "i": return UInt16(kVK_ANSI_I)
    case "j": return UInt16(kVK_ANSI_J)
    case "k": return UInt16(kVK_ANSI_K)
    case "l": return UInt16(kVK_ANSI_L)
    case "m": return UInt16(kVK_ANSI_M)
    case "n": return UInt16(kVK_ANSI_N)
    case "o": return UInt16(kVK_ANSI_O)
    case "p": return UInt16(kVK_ANSI_P)
    case "q": return UInt16(kVK_ANSI_Q)
    case "r": return UInt16(kVK_ANSI_R)
    case "s": return UInt16(kVK_ANSI_S)
    case "t": return UInt16(kVK_ANSI_T)
    case "u": return UInt16(kVK_ANSI_U)
    case "v": return UInt16(kVK_ANSI_V)
    case "w": return UInt16(kVK_ANSI_W)
    case "x": return UInt16(kVK_ANSI_X)
    case "y": return UInt16(kVK_ANSI_Y)
    case "z": return UInt16(kVK_ANSI_Z)
    case "0": return UInt16(kVK_ANSI_0)
    case "1": return UInt16(kVK_ANSI_1)
    case "2": return UInt16(kVK_ANSI_2)
    case "3": return UInt16(kVK_ANSI_3)
    case "4": return UInt16(kVK_ANSI_4)
    case "5": return UInt16(kVK_ANSI_5)
    case "6": return UInt16(kVK_ANSI_6)
    case "7": return UInt16(kVK_ANSI_7)
    case "8": return UInt16(kVK_ANSI_8)
    case "9": return UInt16(kVK_ANSI_9)
    case " ": return UInt16(kVK_Space)
    default: return nil
    }
  }

  public static func displayLabel(for keyCode: UInt16) -> String {
    switch Int(keyCode) {
    case kVK_Space: return "Space"
    case kVK_Return: return "Return"
    case kVK_Tab: return "Tab"
    case kVK_Delete: return "Delete"
    case kVK_Escape: return "Esc"
    case kVK_ForwardDelete: return "Forward Delete"
    case kVK_LeftArrow: return "Left"
    case kVK_RightArrow: return "Right"
    case kVK_UpArrow: return "Up"
    case kVK_DownArrow: return "Down"
    case kVK_Home: return "Home"
    case kVK_End: return "End"
    case kVK_PageUp: return "Page Up"
    case kVK_PageDown: return "Page Down"
    case kVK_F1: return "F1"
    case kVK_F2: return "F2"
    case kVK_F3: return "F3"
    case kVK_F4: return "F4"
    case kVK_F5: return "F5"
    case kVK_F6: return "F6"
    case kVK_F7: return "F7"
    case kVK_F8: return "F8"
    case kVK_F9: return "F9"
    case kVK_F10: return "F10"
    case kVK_F11: return "F11"
    case kVK_F12: return "F12"
    case kVK_ANSI_A: return "A"
    case kVK_ANSI_B: return "B"
    case kVK_ANSI_C: return "C"
    case kVK_ANSI_D: return "D"
    case kVK_ANSI_E: return "E"
    case kVK_ANSI_F: return "F"
    case kVK_ANSI_G: return "G"
    case kVK_ANSI_H: return "H"
    case kVK_ANSI_I: return "I"
    case kVK_ANSI_J: return "J"
    case kVK_ANSI_K: return "K"
    case kVK_ANSI_L: return "L"
    case kVK_ANSI_M: return "M"
    case kVK_ANSI_N: return "N"
    case kVK_ANSI_O: return "O"
    case kVK_ANSI_P: return "P"
    case kVK_ANSI_Q: return "Q"
    case kVK_ANSI_R: return "R"
    case kVK_ANSI_S: return "S"
    case kVK_ANSI_T: return "T"
    case kVK_ANSI_U: return "U"
    case kVK_ANSI_V: return "V"
    case kVK_ANSI_W: return "W"
    case kVK_ANSI_X: return "X"
    case kVK_ANSI_Y: return "Y"
    case kVK_ANSI_Z: return "Z"
    case kVK_ANSI_0: return "0"
    case kVK_ANSI_1: return "1"
    case kVK_ANSI_2: return "2"
    case kVK_ANSI_3: return "3"
    case kVK_ANSI_4: return "4"
    case kVK_ANSI_5: return "5"
    case kVK_ANSI_6: return "6"
    case kVK_ANSI_7: return "7"
    case kVK_ANSI_8: return "8"
    case kVK_ANSI_9: return "9"
    default: return "Key \(keyCode)"
    }
  }
}
