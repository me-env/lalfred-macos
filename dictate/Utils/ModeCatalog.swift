import Foundation
import SwiftUI

struct ModeCatalog {
    struct ModeDefinition: Identifiable {
        let id: String
        let title: String
        let detail: String
        let icon: String
        let iconColor: Color
        let applicationStoreKey: String
        let shortcutStoreKey: String
        let fallbackShortcut: Shortcut
    }

    static let definitions: [ModeDefinition] = [
        ModeDefinition(
            id: "default",
            title: "Default",
            detail: "Standard dictation behavior.",
            icon: "waveform",
            iconColor: .blue,
            applicationStoreKey: AppDefaultsKey.modeDefaultApplicationPath,
            shortcutStoreKey: AppDefaultsKey.shortcutModeDefaultTrigger,
            fallbackShortcut: Shortcut(
                keyCode: KeyCode.from(character: "1") ?? 18,
                modifiers: [.control, .option]
            )
        ),
        ModeDefinition(
            id: "email",
            title: "Email",
            detail: "Optimized for drafting emails.",
            icon: "envelope.fill",
            iconColor: .indigo,
            applicationStoreKey: AppDefaultsKey.modeEmailApplicationPath,
            shortcutStoreKey: AppDefaultsKey.shortcutModeEmailTrigger,
            fallbackShortcut: Shortcut(
                keyCode: KeyCode.from(character: "2") ?? 19,
                modifiers: [.control, .option]
            )
        ),
        ModeDefinition(
            id: "terminal",
            title: "Terminal",
            detail: "Optimized for shell and command workflows.",
            icon: "terminal.fill",
            iconColor: .green,
            applicationStoreKey: AppDefaultsKey.modeTerminalApplicationPath,
            shortcutStoreKey: AppDefaultsKey.shortcutModeTerminalTrigger,
            fallbackShortcut: Shortcut(
                keyCode: KeyCode.from(character: "3") ?? 20,
                modifiers: [.control, .option]
            )
        )
    ]
}
