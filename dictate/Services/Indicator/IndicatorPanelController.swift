import SwiftUI
import AppKit

@MainActor
final class IndicatorPanelController {
  private let indicatorController: IndicatorBubblePanelController
  private var delayedHideTask: Task<Void, Never>?

  init() {
    self.indicatorController = IndicatorBubblePanelController()
  }

  // MARK: - Public API

  func showListening() {
    indicatorController.showListening()
    showIndicator(autoHideAfter: nil)
  }

  func updateListeningLevel(_ level: CGFloat) {
    indicatorController.updateListeningLevel(level)
  }

  func showStatus(message: String, autoHideAfter delay: TimeInterval? = nil) {
    indicatorController.showStatus(message: message)
    showIndicator(autoHideAfter: delay)
  }

  func hideIndicator() {
    delayedHideTask?.cancel()
    indicatorController.hide()
  }

  // MARK: - Private

  private func showIndicator(autoHideAfter delay: TimeInterval?) {
    delayedHideTask?.cancel()
    let wasVisible = indicatorController.isVisible
    indicatorController.setShouldAnimateAppearance(!wasVisible)
    indicatorController.resize(
      to: .small,
      animated: wasVisible
    )

    indicatorController.present()

    guard let delay else { return }
    delayedHideTask = Task {
      try? await Task.sleep(for: .seconds(delay))
      guard !Task.isCancelled else { return }
      indicatorController.hide()
    }
  }
}
