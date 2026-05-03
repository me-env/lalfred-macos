import SwiftUI
import AppKit
import Observation

@MainActor
final class ModeSwitcherPanelController {
  private let panel: OverlayPanel
  private let viewModel: CommandViewModel
  private let hostingController: NSHostingController<AnyView>
  private let panelWidth: CGFloat
  private var isPresented = false
  private var isDismissing = false

  convenience init(viewModel: CommandViewModel) {
    self.init(viewModel: viewModel, size: IndicatorPanelMetrics.commandPanelSize)
  }

  init(
    viewModel: CommandViewModel,
    size: CGSize
  ) {
    self.viewModel = viewModel
    self.panelWidth = size.width
    self.hostingController = NSHostingController(
      rootView: AnyView(
        CommandPanelView(viewModel: viewModel)
          .frame(width: size.width, alignment: .topLeading)
      )
    )
    self.panel = OverlayPanel(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    configureOverlayPanel(panel)
    panel.ignoresMouseEvents = false
    panel.onResignKey = { [weak self] in
      guard let self else { return }
      guard self.isPresented, !self.isDismissing else { return }
      self.onDismiss?()
    }
    panel.contentViewController = hostingController
    observeContentChanges()
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
    isDismissing = false
    isPresented = true
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
    resizeToFittingContentIfNeeded(animated: false)
  }

  func dismiss() {
    guard isPresented else { return }
    isDismissing = true

    let activePanel = panel
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.12
      context.timingFunction = CAMediaTimingFunction(name: .easeIn)
      activePanel.animator().alphaValue = 0
    } completionHandler: {
      Task { @MainActor in
        activePanel.orderOut(nil)
        activePanel.allowsKey = false
        self.isPresented = false
        self.isDismissing = false
      }
    }
  }

  private func observeContentChanges() {
    withObservationTracking {
      _ = viewModel.query
      _ = viewModel.suggestions.count
      _ = viewModel.activeModeTitle
    } onChange: { [weak self] in
      guard let self else { return }
      Task { @MainActor [weak self] in
        self?.resizeToFittingContentIfNeeded(animated: true)
        self?.observeContentChanges()
      }
    }
  }

  private func resizeToFittingContentIfNeeded(animated: Bool) {
    guard isPresented, !isDismissing else { return }

    hostingController.view.layoutSubtreeIfNeeded()
    let fittingHeight = ceil(hostingController.view.fittingSize.height)
    let targetHeight = max(
      IndicatorPanelMetrics.commandPanelMinHeight,
      min(IndicatorPanelMetrics.commandPanelMaxHeight, fittingHeight)
    )

    let currentFrame = panel.frame
    guard abs(currentFrame.height - targetHeight) > 0.5 || abs(currentFrame.width - panelWidth) > 0.5 else {
      return
    }

    let targetFrame = NSRect(
      x: currentFrame.minX,
      y: currentFrame.maxY - targetHeight,
      width: panelWidth,
      height: targetHeight
    )

    setOverlayPanelFrame(
      panel,
      to: targetFrame,
      animated: animated,
      duration: 0.12,
      timingFunction: CAMediaTimingFunction(name: .easeInEaseOut)
    )
  }
}
