import SwiftUI
import AppKit


@MainActor
final class IndicatorPanelController {
  private let indicatorController: IndicatorBubblePanelController
  private let modeSwitcherController: ModeSwitcherPanelController
  private let modeCatalog: ModeCatalog
  private var hideTask: Task<Void, Never>?
  private var previouslyFrontmostApplication: NSRunningApplication?
  private var isCommandVisible = false
  
  var onModeSwitcherSubmit: ((String) -> Void)?
  var onModeSwitcherDismiss: (() -> Void)?
  var isModeSwitcherVisible: Bool { isCommandVisible }
  
  init(modeCatalog: ModeCatalog) {
    self.modeCatalog = modeCatalog
    
    self.indicatorController = IndicatorBubblePanelController(
      viewModel: IndicatorViewModel(),
      size: IndicatorPanelLayout.compactBubbleSize
    )
    
    self.modeSwitcherController = ModeSwitcherPanelController(
      viewModel: CommandViewModel(modeCatalog: modeCatalog),
      size: IndicatorPanelLayout.commandPanelSize
    )
    
    modeSwitcherController.onSubmit = { [weak self] value in
      _ = self?.modeCatalog.selectMode(matching: value)
      self?.dismissModeSwitcher(notify: false)
      self?.onModeSwitcherSubmit?(value)
    }
    modeSwitcherController.onDismiss = { [weak self] in
      self?.dismissModeSwitcher(notify: false)
      self?.onModeSwitcherDismiss?()
    }
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
    hideTask?.cancel()
    indicatorController.hide()
  }
  
  func showModeSwitcher() {
    hideTask?.cancel()
    capturePreviouslyFrontmostApplicationIfNeeded()
    isCommandVisible = true
    
    let indFrame = indicatorController.frame(for: .big)
    indicatorController.resize(
      to: .big,
      animated: indicatorController.isVisible
    )
    
    modeSwitcherController.reset()
    modeSwitcherController.present(below: indFrame)
  }
  
  func dismissModeSwitcher() {
    dismissModeSwitcher(notify: true)
  }
  
  // MARK: - Private
  
  private func showIndicator(autoHideAfter delay: TimeInterval?) {
    hideTask?.cancel()
    let wasVisible = indicatorController.isVisible
    indicatorController.setShouldAnimateAppearance(!wasVisible)
    
    if !isCommandVisible {
      indicatorController.resize(
        to: .small,
        animated: wasVisible
      )
    }
    
    indicatorController.present()
    
    guard let delay else { return }
    hideTask = Task {
      try? await Task.sleep(for: .seconds(delay))
      guard !Task.isCancelled else { return }
      indicatorController.hide()
    }
  }
  
  private func dismissModeSwitcher(notify: Bool) {
    guard isCommandVisible else { return }
    isCommandVisible = false
    modeSwitcherController.dismiss()
    
    indicatorController.resize(
      to: .small,
      animated: true
    )
    
    restorePreviouslyFrontmostApplicationFocusIfNeeded()
    if notify { onModeSwitcherDismiss?() }
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

