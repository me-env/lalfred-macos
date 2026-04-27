//
//  GlobalHotKeyMonitor.swift
//  dictate
//
//  Created by Codex on 4/26/26.
//

import Foundation
import Carbon.HIToolbox

final class GlobalHotKeyMonitor {
    private let shortcutStore = ShortcutDefaultsStore(key: "shortcut.toggleRecording")
    private let fallbackShortcut = Shortcut(
        keyCode: KeyCode.from(character: " ") ?? UInt16(kVK_Space),
        modifiers: [.control, .option]
    )

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let hotKeyID = EventHotKeyID(signature: OSType(0x44494354), id: 1) // 'DICT'

    private let onTrigger: @MainActor () -> Void

    init(onTrigger: @escaping @MainActor () -> Void) {
        self.onTrigger = onTrigger
        installHandlerIfNeeded()
        registerCurrentShortcut()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShortcutChange),
            name: .shortcutDidChange,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        unregisterHotKey()

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    @objc private func handleShortcutChange() {
        registerCurrentShortcut()
    }

    private func installHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event,
                      let userData else {
                    return noErr
                }

                let monitor = Unmanaged<GlobalHotKeyMonitor>.fromOpaque(userData).takeUnretainedValue()

                var receivedID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &receivedID
                )

                guard status == noErr,
                      receivedID.id == monitor.hotKeyID.id,
                      receivedID.signature == monitor.hotKeyID.signature else {
                    return OSStatus(eventNotHandledErr)
                }

                Task { @MainActor in
                    monitor.onTrigger()
                }
                return noErr
            },
            1,
            &eventSpec,
            selfPointer,
            &eventHandlerRef
        )
    }

    private func registerCurrentShortcut() {
        unregisterHotKey()

        let shortcut = shortcutStore.load() ?? fallbackShortcut
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status != noErr {
            hotKeyRef = nil
            print("Failed to register hot key: \(status)")
        }
    }

    private func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }
}
