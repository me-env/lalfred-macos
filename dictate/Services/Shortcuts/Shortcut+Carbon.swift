import Carbon.HIToolbox

extension Shortcut {
    var carbonModifiers: UInt32 {
        var flags: UInt32 = 0

        if modifiers.contains(.command) {
            flags |= UInt32(cmdKey)
        }
        if modifiers.contains(.option) {
            flags |= UInt32(optionKey)
        }
        if modifiers.contains(.control) {
            flags |= UInt32(controlKey)
        }
        if modifiers.contains(.shift) {
            flags |= UInt32(shiftKey)
        }

        return flags
    }
}
