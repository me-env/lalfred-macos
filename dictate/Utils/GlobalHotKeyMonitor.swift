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

    private let monitor: CarbonHotKeyMonitor

    init(
        id: UInt32 = 1,
        storeKey: String = AppDefaultsKey.shortcutToggleRecording,
        fallbackShortcut: Shortcut = Shortcut(
            keyCode: KeyCode.from(character: " ") ?? UInt16(kVK_Space),
            modifiers: [.control, .option]
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
        monitor.activate()
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
