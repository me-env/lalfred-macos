import AppKit

@MainActor
final class OverlayPanel: NSPanel {
  var allowsKey = false

  override var canBecomeKey: Bool { allowsKey }
  override var canBecomeMain: Bool { false }
}

@MainActor
func configureOverlayPanel(_ panel: OverlayPanel) {
  panel.isReleasedWhenClosed = false
  panel.hasShadow = true
  panel.backgroundColor = .clear
  panel.isOpaque = false
  panel.level = .statusBar
  panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
  panel.hidesOnDeactivate = false
}

@MainActor
func setOverlayPanelFrame(
  _ panel: OverlayPanel,
  to frame: NSRect,
  animated: Bool,
  duration: TimeInterval = 0.18,
  timingFunction: CAMediaTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut),
  completion: (() -> Void)? = nil
) {
  guard animated else {
    panel.setFrame(frame, display: false)
    completion?()
    return
  }

  NSAnimationContext.runAnimationGroup { context in
    context.duration = duration
    context.timingFunction = timingFunction
    panel.animator().setFrame(frame, display: false)
  } completionHandler: {
    completion?()
  }
}
