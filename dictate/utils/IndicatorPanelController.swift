//
//  IndicatorPanelController.swift
//  dictate
//
//  Created by Codex on 4/26/26.
//

import SwiftUI
import AppKit

@MainActor
final class IndicatorPanelController {
    private final class NonActivatingPanel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private enum Layout {
        static let width: CGFloat = 260
        static let height: CGFloat = 90
        static let topInset: CGFloat = 20
    }

    private let panel: NSPanel
    private let hostingController: NSHostingController<IndicatorView>
    private var hideTask: Task<Void, Never>?

    init() {
        let content = IndicatorView(message: "", tint: .blue)
        hostingController = NSHostingController(rootView: content)

        panel = NonActivatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.isReleasedWhenClosed = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.contentViewController = hostingController
    }

    func show(message: String, tint: Color, autoHideAfter delay: TimeInterval? = nil) {
        hideTask?.cancel()
        hostingController.rootView = IndicatorView(message: message, tint: tint)
        positionAtTopCenter()
        panel.orderFrontRegardless()

        guard let delay else { return }

        hideTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
        }
    }

    func hide() {
        hideTask?.cancel()
        panel.orderOut(nil)
    }

    private func positionAtTopCenter() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let x = frame.midX - (Layout.width / 2)
        let y = frame.maxY - Layout.height - Layout.topInset
        panel.setFrame(NSRect(x: x, y: y, width: Layout.width, height: Layout.height), display: false)
    }
}

private struct IndicatorView: View {
    let message: String
    let tint: Color
    @State private var isPresented = false

    var body: some View {
        VStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(tint)
                .frame(width: 56, height: 6)
            Text(message)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.55)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 18)
        .frame(width: 180, height: 42)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        }
        .scaleEffect(isPresented ? 1 : 0.01, anchor: .top)
        .opacity(isPresented ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                isPresented = true
            }
        }
    }
}

#Preview {
  IndicatorView(message: "hello", tint: Color.orange)
}
