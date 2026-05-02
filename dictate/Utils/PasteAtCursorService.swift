//
//  PasteAtCursorService.swift
//  dictate
//
//  Created by Codex on 4/26/26.
//

import AppKit
import CoreGraphics

struct PasteAtCursorService {
    private let accessibilityPermissionService = AccessibilityPermissionService()

    func paste(_ text: String) -> Bool {
        print("[PasteAtCursorService] paste() called. text='\(text)'")

        let trusted = accessibilityPermissionService.isTrusted()
        print("[PasteAtCursorService] Accessibility trusted: \(trusted)")
        guard trusted else {
            _ = accessibilityPermissionService.requestPrompt()
            print("[PasteAtCursorService] Aborting: accessibility permission is not granted")
            print("[PasteAtCursorService] Current bundle id: \(Bundle.main.bundleIdentifier ?? "nil")")
            print("[PasteAtCursorService] Current bundle path: \(Bundle.main.bundlePath)")
            print("[PasteAtCursorService] Current process id: \(ProcessInfo.processInfo.processIdentifier)")
            return false
        }

        let frontmostApp = NSWorkspace.shared.frontmostApplication
        print("[PasteAtCursorService] Frontmost app: \(frontmostApp?.localizedName ?? "unknown") (pid: \(frontmostApp?.processIdentifier ?? -1))")

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let didWritePasteboard = pasteboard.setString(text, forType: .string)
        print("[PasteAtCursorService] Pasteboard write success: \(didWritePasteboard)")
        guard didWritePasteboard else {
            print("[PasteAtCursorService] Aborting: failed to write pasteboard")
            return false
        }

        guard let source = CGEventSource(stateID: .hidSystemState) else {
            print("[PasteAtCursorService] Aborting: failed to create CGEventSource")
            return false
        }

        guard let vDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(9), keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(9), keyDown: false) else {
            print("[PasteAtCursorService] Aborting: failed to create keyboard CGEvents")
            return false
        }

        print("[PasteAtCursorService] Posting Cmd+V events (command on keyDown only)")
        vDown.flags = .maskCommand
        vDown.post(tap: .cghidEventTap)

        vUp.flags = []
        vUp.post(tap: .cghidEventTap)

        print("[PasteAtCursorService] Cmd+V events posted")
        return true
    }
}
