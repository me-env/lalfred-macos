import SwiftUI
import AppKit
import Observation

struct ModeSuggestion: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let detail: String
}

@MainActor
final class IndicatorPanelController {
    enum BubbleContent: Equatable {
        case listening(level: CGFloat)
        case status(message: String)
    }

    private final class OverlayPanel: NSPanel {
        var allowsKey = false
        override var canBecomeKey: Bool { allowsKey }
        override var canBecomeMain: Bool { false }
    }

    @Observable
    final class IndicatorViewModel {
        var bubbleContent: BubbleContent = .status(message: "")
        var shouldAnimateAppearance = false
    }

    @Observable
    final class CommandViewModel {
        private let modeStateStore: ModeStateStore

        var query: String = ""
        var suggestions: [ModeSuggestion] = []
        @ObservationIgnored var onSubmit: ((String) -> Void)?
        @ObservationIgnored var onDismiss: (() -> Void)?

        init(modeStateStore: ModeStateStore) {
            self.modeStateStore = modeStateStore
        }

        func filteredSuggestions(for query: String) -> [ModeSuggestion] {
            modeStateStore.filteredSuggestions(for: query)
        }

        func reset() {
            query = ""
            suggestions = modeStateStore.filteredSuggestions(for: "")
        }
    }

    private enum Layout {
        static let compactBubbleWidth: CGFloat = 55
        static let compactBubbleHeight: CGFloat = 22.5
        static let expandedTextBubbleMinWidth: CGFloat = 176
        static let expandedTextBubbleMaxWidth: CGFloat = 300
        static let expandedTextBubbleMinHeight: CGFloat = 58
        static let expandedTextBubbleMaxHeight: CGFloat = 112
        static let commandPanelWidth: CGFloat = 320
        static let commandPanelHeight: CGFloat = 200
        static let panelGap: CGFloat = 6
        static let topInset: CGFloat = 20
    }

    private let indicatorPanel: OverlayPanel
    private let commandPanel: OverlayPanel
    private let modeStateStore: ModeStateStore
    private let indicatorViewModel: IndicatorViewModel
    private let commandViewModel: CommandViewModel
    private var hideTask: Task<Void, Never>?
    private var previouslyFrontmostApplication: NSRunningApplication?
    private var isCommandVisible = false

    var onModeSwitcherSubmit: ((String) -> Void)?
    var onModeSwitcherDismiss: (() -> Void)?
    var isModeSwitcherVisible: Bool { isCommandVisible }

    init(modeStateStore: ModeStateStore) {
        self.modeStateStore = modeStateStore
        self.indicatorViewModel = IndicatorViewModel()
        self.commandViewModel = CommandViewModel(modeStateStore: modeStateStore)

        indicatorPanel = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: Layout.compactBubbleWidth, height: Layout.compactBubbleHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        Self.configurePanel(indicatorPanel)
        indicatorPanel.ignoresMouseEvents = true
        indicatorPanel.contentViewController = NSHostingController(
            rootView: IndicatorBubbleView(viewModel: indicatorViewModel)
        )

        commandPanel = OverlayPanel(
            contentRect: NSRect(x: 0, y: 0, width: Layout.commandPanelWidth, height: Layout.commandPanelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        Self.configurePanel(commandPanel)
        commandPanel.ignoresMouseEvents = false
        commandPanel.contentViewController = NSHostingController(
            rootView: CommandPanelView(viewModel: commandViewModel)
        )

        commandViewModel.onSubmit = { [weak self] value in
            _ = self?.modeStateStore.selectMode(matching: value)
            self?.dismissModeSwitcher(notify: false)
            self?.onModeSwitcherSubmit?(value)
        }
        commandViewModel.onDismiss = { [weak self] in
            self?.dismissModeSwitcher(notify: false)
            self?.onModeSwitcherDismiss?()
        }
    }

    private static func configurePanel(_ panel: OverlayPanel) {
        panel.isReleasedWhenClosed = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
    }

    // MARK: - Public API

    func showListening() {
        indicatorViewModel.bubbleContent = .listening(level: 0)
        showIndicator(autoHideAfter: nil)
    }

    func updateListeningLevel(_ level: CGFloat) {
        indicatorViewModel.bubbleContent = .listening(level: max(0, min(level, 1)))
    }

    func showStatus(message: String, autoHideAfter delay: TimeInterval? = nil) {
        indicatorViewModel.bubbleContent = .status(message: message)
        showIndicator(autoHideAfter: delay)
    }

    func showModeSwitcher() {
        hideTask?.cancel()
        capturePreviouslyFrontmostApplicationIfNeeded()
        isCommandVisible = true

        let expandedSize = CGSize(width: Layout.commandPanelWidth, height: Layout.compactBubbleHeight)
        let indFrame = indicatorFrame(for: expandedSize)
        setFrame(indicatorPanel, frame: indFrame, animated: indicatorPanel.isVisible, duration: 0.09)

        commandViewModel.reset()
        let cmdFrame = commandFrame(below: indFrame)
        commandPanel.setFrame(cmdFrame, display: false)
        commandPanel.alphaValue = 0
        commandPanel.allowsKey = true
        commandPanel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.commandPanel.animator().alphaValue = 1
        }

        commandPanel.makeKey()
    }

    func dismissModeSwitcher() {
        dismissModeSwitcher(notify: true)
    }

    // MARK: - Private

    private func showIndicator(autoHideAfter delay: TimeInterval?) {
        hideTask?.cancel()
        let wasVisible = indicatorPanel.isVisible
        indicatorViewModel.shouldAnimateAppearance = !wasVisible

        if !isCommandVisible {
            let size = indicatorSize(for: indicatorViewModel.bubbleContent)
            let frame = indicatorFrame(for: size)
            setFrame(indicatorPanel, frame: frame, animated: wasVisible)
        }

        indicatorPanel.alphaValue = 1
        indicatorPanel.allowsKey = false
        indicatorPanel.ignoresMouseEvents = true
        indicatorPanel.orderFrontRegardless()

        guard let delay else { return }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            indicatorPanel.orderOut(nil)
        }
    }

    private func dismissModeSwitcher(notify: Bool) {
        guard isCommandVisible else { return }
        isCommandVisible = false

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.commandPanel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.commandPanel.orderOut(nil)
            self?.commandPanel.allowsKey = false
        }

        let size = indicatorSize(for: indicatorViewModel.bubbleContent)
        let frame = indicatorFrame(for: size)
        setFrame(indicatorPanel, frame: frame, animated: true, duration: 0.09)

        restorePreviouslyFrontmostApplicationFocusIfNeeded()
        if notify { onModeSwitcherDismiss?() }
    }

    private func setFrame(_ panel: OverlayPanel, frame: NSRect, animated: Bool, duration: TimeInterval = 0.18) {
        guard animated else {
            panel.setFrame(frame, display: false)
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: false)
        }
    }

    // MARK: - Layout

    private func indicatorFrame(for size: CGSize) -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(origin: .zero, size: size)
        }
        let visibleFrame = screen.visibleFrame
        let x = visibleFrame.midX - (size.width / 2)
        let y = visibleFrame.maxY - Layout.topInset - size.height
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func commandFrame(below indFrame: NSRect) -> NSRect {
        let x = indFrame.midX - (Layout.commandPanelWidth / 2)
        let y = indFrame.minY - Layout.panelGap - Layout.commandPanelHeight
        return NSRect(x: x, y: y, width: Layout.commandPanelWidth, height: Layout.commandPanelHeight)
    }

    private func indicatorSize(for content: BubbleContent) -> CGSize {
        switch content {
        case .listening:
            return CGSize(width: Layout.compactBubbleWidth, height: Layout.compactBubbleHeight)
        case .status(let message):
            return statusSize(for: message)
        }
    }

    private func statusSize(for message: String) -> CGSize {
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "processing" || normalized == "cancel" || normalized == "pasted" {
            return CGSize(width: Layout.compactBubbleWidth, height: Layout.compactBubbleHeight)
        }
        let textSize = measuredTextSize(for: message)
        let width = min(Layout.expandedTextBubbleMaxWidth, max(Layout.expandedTextBubbleMinWidth, textSize.width + 56))
        let height = min(Layout.expandedTextBubbleMaxHeight, max(Layout.expandedTextBubbleMinHeight, textSize.height + 30))
        return CGSize(width: width, height: height)
    }

    private func measuredTextSize(for message: String) -> CGSize {
        let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        let rect = (message as NSString).boundingRect(
            with: CGSize(width: 220, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return CGSize(width: ceil(rect.width), height: ceil(rect.height))
    }

    // MARK: - Focus Management

    private func capturePreviouslyFrontmostApplicationIfNeeded() {
        guard let frontmost = NSWorkspace.shared.frontmostApplication,
              frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            previouslyFrontmostApplication = nil
            return
        }
        previouslyFrontmostApplication = frontmost
    }

    private func restorePreviouslyFrontmostApplicationFocusIfNeeded() {
        guard let app = previouslyFrontmostApplication else { return }
        app.activate(options: [])
        previouslyFrontmostApplication = nil
    }
}
