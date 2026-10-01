import SwiftUI
import AppKit

@MainActor
final class IndicatorBubblePanelController {
  enum PanelSize {
    case small
    case big
  }

  private let panel: OverlayPanel
  private let viewModel: IndicatorViewModel

  init(
    viewModel: IndicatorViewModel,
    size: CGSize
  ) {
    self.viewModel = viewModel
    self.panel = OverlayPanel(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    configureOverlayPanel(panel)
    panel.ignoresMouseEvents = true
    panel.contentViewController = NSHostingController(
      rootView: IndicatorBubbleView(viewModel: viewModel)
    )
  }

  var isVisible: Bool { panel.isVisible }
  var bubbleContent: IndicatorBubbleContent { viewModel.bubbleContent }

  func showPreparing() {
    viewModel.bubbleContent = .preparing
  }

  func showListening() {
    viewModel.bubbleContent = .listening(level: 0)
  }

  func updateListeningLevel(_ level: CGFloat) {
    viewModel.bubbleContent = .listening(level: max(0, min(level, 1)))
  }

  func showStatus(message: String) {
    viewModel.bubbleContent = .status(message: message)
  }

  func setShouldAnimateAppearance(_ shouldAnimate: Bool) {
    viewModel.shouldAnimateAppearance = shouldAnimate
  }

  func present() {
    panel.alphaValue = 1
    panel.allowsKey = false
    panel.ignoresMouseEvents = true
    panel.orderFrontRegardless()
  }

  func hide() {
    panel.orderOut(nil)
  }

  func frame(for panelSize: PanelSize) -> NSRect {
    let size = resolvedSize(for: panelSize)
    return IndicatorPanelLayout.indicatorFrame(for: size)
  }

  func resize(to panelSize: PanelSize, animated: Bool) {
    let targetFrame = frame(for: panelSize)
    animateResize(to: targetFrame, animated: animated)
  }

  private func resolvedSize(for panelSize: PanelSize) -> CGSize {
    switch panelSize {
    case .small:
      return IndicatorPanelLayout.indicatorSize(for: viewModel.bubbleContent)
    case .big:
      return CGSize(
        width: IndicatorPanelMetrics.compactBubbleSize.width * IndicatorPanelMetrics.expandedIndicatorScale,
        height: IndicatorPanelMetrics.compactBubbleSize.height * IndicatorPanelMetrics.expandedIndicatorScale
      )
    }
  }

  private func animateResize(to targetFrame: NSRect, animated: Bool) {
    guard animated else {
      setOverlayPanelFrame(panel, to: targetFrame, animated: false)
      return
    }

    // A single ease-out, without overshoot: large text bubbles grow a lot, so any overshoot
    // turned into a visible bounce.
    setOverlayPanelFrame(
      panel,
      to: targetFrame,
      animated: true,
      duration: IndicatorPanelMetrics.indicatorResizeDuration,
      timingFunction: CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
    )
  }
}
