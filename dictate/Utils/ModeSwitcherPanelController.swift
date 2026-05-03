import SwiftUI
import AppKit

@MainActor
final class ModeSwitcherPanelController {
  private let panel: OverlayPanel
  private let viewModel: CommandViewModel

  init(viewModel: CommandViewModel, size: CGSize) {
    self.viewModel = viewModel
    self.panel = OverlayPanel(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    configureOverlayPanel(panel)
    panel.ignoresMouseEvents = false
    panel.contentViewController = NSHostingController(
      rootView: CommandPanelView(viewModel: viewModel)
    )
  }

  var onSubmit: ((String) -> Void)? {
    get { viewModel.onSubmit }
    set { viewModel.onSubmit = newValue }
  }

  var onDismiss: (() -> Void)? {
    get { viewModel.onDismiss }
    set { viewModel.onDismiss = newValue }
  }

  func reset() {
    viewModel.reset()
  }

  func present(below indicatorFrame: NSRect) {
    let frame = IndicatorPanelLayout.commandFrame(below: indicatorFrame)
    panel.setFrame(frame, display: false)
    panel.alphaValue = 0
    panel.allowsKey = true
    panel.orderFrontRegardless()

    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.15
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      panel.animator().alphaValue = 1
    }

    panel.makeKey()
  }

  func dismiss() {
    let activePanel = panel
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.12
      context.timingFunction = CAMediaTimingFunction(name: .easeIn)
      activePanel.animator().alphaValue = 0
    } completionHandler: {
      Task { @MainActor in
        activePanel.orderOut(nil)
        activePanel.allowsKey = false
      }
    }
  }
}
