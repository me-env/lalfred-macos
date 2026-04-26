//
//  AppRuntimeCoordinator.swift
//  dictate
//
//  Created by Codex on 4/26/26.
//

import SwiftUI

@MainActor
final class AppRuntimeCoordinator {
    private enum RuntimeState {
        case idle
        case listening
        case processing
    }

    private let indicator = IndicatorPanelController()
    private let pasteService = PasteAtCursorService()
    private var hotKeyMonitor: GlobalHotKeyMonitor?
    private var state: RuntimeState = .idle
    private var lastPressDate: Date = .distantPast
    private let minimumPressInterval: TimeInterval = 0.30

    func start() {
        guard hotKeyMonitor == nil else { return }

        print("[AppRuntimeCoordinator] Starting runtime coordinator")
        hotKeyMonitor = GlobalHotKeyMonitor { [weak self] in
            self?.handleShortcutPress()
        }
    }

    private func handleShortcutPress() {
        let now = Date()
        if now.timeIntervalSince(lastPressDate) < minimumPressInterval {
            print("[AppRuntimeCoordinator] Ignored shortcut press due to debounce")
            return
        }
        lastPressDate = now

        print("[AppRuntimeCoordinator] Shortcut pressed. state=\(String(describing: state))")

        switch state {
        case .idle:
            state = .listening
            indicator.show(message: "Listening…", tint: .green)
            print("[AppRuntimeCoordinator] Indicator set to Listening")

        case .listening:
            state = .processing
            Task {
                await fakeProcessAndPasteResponse()
            }

        case .processing:
            print("[AppRuntimeCoordinator] Ignored shortcut press while processing")
        }
    }

    private func fakeProcessAndPasteResponse() async {
        print("[AppRuntimeCoordinator] Fake processing started")
        indicator.show(message: "Processing…", tint: .orange)

        try? await Task.sleep(for: .seconds(0.8))

        let responseText = "Oui"
        print("[AppRuntimeCoordinator] Fake API response: '\(responseText)'")
        let didPaste = pasteService.paste(responseText)
        print("[AppRuntimeCoordinator] pasteService result: \(didPaste)")

        if didPaste {
            indicator.show(message: "Pasted: \(responseText)", tint: .blue, autoHideAfter: 1.0)
            print("[AppRuntimeCoordinator] Indicator set to pasted success")
        } else {
            indicator.show(message: "Paste failed (check Accessibility)", tint: .red, autoHideAfter: 1.6)
            print("[AppRuntimeCoordinator] Indicator set to paste failure")
        }

        state = .idle
    }
}
