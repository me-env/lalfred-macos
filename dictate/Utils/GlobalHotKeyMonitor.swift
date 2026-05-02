//
//  GlobalHotKeyMonitor.swift
//  dictate
//
//  Created by Codex on 4/26/26.
//

import Foundation
import Carbon.HIToolbox

final class GlobalHotKeyMonitor {
    private let shortcutStore: ShortcutDefaultsStore
    private let spaceKeyCode = KeyCode.from(character: " ") ?? UInt16(kVK_Space)

    private let monitor: CarbonHotKeyMonitor

    init(
        id: UInt32 = 1,
        storeKey: String = AppDefaultsKey.shortcutToggleRecording,
        fallbackShortcut: Shortcut = Shortcut(
            keyCode: KeyCode.from(character: " ") ?? UInt16(kVK_Space),
            modifiers: [.command, .shift]
        ),
        onTrigger: @escaping @MainActor () -> Void
    ) {
        self.shortcutStore = ShortcutDefaultsStore(key: storeKey)
        shortcutStore.ensureDefault(fallbackShortcut)

        monitor = CarbonHotKeyMonitor(
            id: id,
            shortcutProvider: { [shortcutStore] in
                shortcutStore.load()
            },
            reloadOnShortcutChange: true,
            onKeyDown: onTrigger
        )
        migrateIncompatibleShortcutIfNeeded(defaultShortcut: fallbackShortcut)
        monitor.activate()
    }

    private func migrateIncompatibleShortcutIfNeeded(defaultShortcut: Shortcut) {
        let incompatibleShortcut = Shortcut(
            keyCode: spaceKeyCode,
            modifiers: [.command]
        )
        guard shortcutStore.load() == incompatibleShortcut else { return }
        shortcutStore.save(defaultShortcut)
        NotificationCenter.default.post(name: .shortcutDidChange, object: nil)
    }

    func activate() {
        monitor.activate()
    }

    func deactivate() {
        monitor.deactivate()
    }

    deinit {
        monitor.deactivate()
    }
}
