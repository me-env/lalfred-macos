import Carbon.HIToolbox

enum AppDefaultShortcuts {
  static let toggleRecording = Shortcut(
    keyCode: KeyCode.from(character: " ") ?? UInt16(kVK_Space),
    modifiers: [.command, .shift]
  )

  static let holdToSpeak = Shortcut(
    keyCode: Shortcut.modifierOnlyKeyCode,
    modifiers: [.option, .control]
  )

  static let escape = Shortcut(
    keyCode: UInt16(kVK_Escape),
    modifiers: []
  )
}
