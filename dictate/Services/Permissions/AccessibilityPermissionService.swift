//
//  AccessibilityPermissionService.swift
//  dictate
//
//  Created by Codex on 4/26/26.
//

import Foundation
import ApplicationServices
import AppKit

struct AccessibilityPermissionService {
    func isTrusted() -> Bool {
        AXIsProcessTrustedWithOptions(nil)
    }

    func requestPrompt() -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: kCFBooleanTrue as Any
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func openSettings() {
        guard let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(settingsURL)
    }
}
