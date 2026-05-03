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

  init(viewModel: IndicatorViewModel, size: CGSize) {
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
        width: IndicatorPanelLayout.compactBubbleSize.width * IndicatorPanelLayout.modeSwitcherIndicatorScale,
        height: IndicatorPanelLayout.compactBubbleSize.height * IndicatorPanelLayout.modeSwitcherIndicatorScale
      )
    }
  }

  private func animateResize(to targetFrame: NSRect, animated: Bool) {
    guard animated else {
      setOverlayPanelFrame(panel, to: targetFrame, animated: false)
      return
    }

    let current = panel.frame
    let overshootFactor = IndicatorPanelLayout.modeSwitcherOvershootFactor
    let overshootFrame = NSRect(
      x: targetFrame.origin.x + ((targetFrame.origin.x - current.origin.x) * overshootFactor),
      y: targetFrame.origin.y + ((targetFrame.origin.y - current.origin.y) * overshootFactor),
      width: targetFrame.size.width + ((targetFrame.size.width - current.size.width) * overshootFactor),
      height: targetFrame.size.height + ((targetFrame.size.height - current.size.height) * overshootFactor)
    )

    let firstDuration = IndicatorPanelLayout.modeSwitcherResizeDuration * 0.62
    let secondDuration = IndicatorPanelLayout.modeSwitcherResizeDuration * 0.38

    setOverlayPanelFrame(
      panel,
      to: overshootFrame,
      animated: true,
      duration: firstDuration,
      timingFunction: CAMediaTimingFunction(name: .easeOut)
    )

    Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(firstDuration))
      guard let self else { return }
      setOverlayPanelFrame(
        self.panel,
        to: targetFrame,
        animated: true,
        duration: secondDuration,
        timingFunction: CAMediaTimingFunction(name: .easeInEaseOut)
      )
    }
  }
}
