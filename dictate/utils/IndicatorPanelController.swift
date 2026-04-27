//
//  IndicatorPanelController.swift
//  dictate
//
//  Created by Codex on 4/26/26.
//

import SwiftUI
import AppKit
import Combine

@MainActor
final class IndicatorPanelController {
  enum Content {
    case listening(level: CGFloat)
    case status(message: String)
  }

  private final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
  }

  fileprivate final class ViewModel: ObservableObject {
    @Published var content: Content = .status(message: "")
    @Published var shouldAnimateAppearance = false
  }
  
  private enum Layout {
    static let width: CGFloat = 110
    static let height: CGFloat = 45
    static let topInset: CGFloat = 20
  }
  
  private let panel: NSPanel
  private let viewModel = ViewModel()
  private let hostingController: NSHostingController<IndicatorView>
  private var hideTask: Task<Void, Never>?
  
  init() {
    let content = IndicatorView(viewModel: viewModel)
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
  
  func showListening() {
    show(content: .listening(level: 0), autoHideAfter: nil)
  }

  func updateListeningLevel(_ level: CGFloat) {
    guard case .listening = viewModel.content else { return }
    let clampedLevel = max(0, min(level, 1))
    viewModel.content = .listening(level: clampedLevel)
  }

  func showStatus(message: String, autoHideAfter delay: TimeInterval? = nil) {
    show(content: .status(message: message), autoHideAfter: delay)
  }

  private func show(content: Content, autoHideAfter delay: TimeInterval? = nil) {
    hideTask?.cancel()
    let shouldAnimateAppearance = !panel.isVisible
    viewModel.content = content
    viewModel.shouldAnimateAppearance = shouldAnimateAppearance
    
    let targetFrame = centeredFrame(width: Layout.width, height: Layout.height)
    panel.setFrame(targetFrame, display: false)
    panel.alphaValue = 1
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
  
  private func centeredFrame(width: CGFloat, height: CGFloat) -> NSRect {
    guard let screen = NSScreen.main else { return NSRect(x: 0, y: 0, width: width, height: height) }
    let frame = screen.visibleFrame
    let topEdge = frame.maxY - Layout.topInset
    let x = frame.midX - (width / 2)
    // Keep a fixed top edge so the panel grows without drifting vertically.
    let y = topEdge - height
    return NSRect(x: x, y: y, width: width, height: height)
  }
}

private struct IndicatorView: View {
  @ObservedObject var viewModel: IndicatorPanelController.ViewModel
  
  @State private var scale: CGFloat = 0.01
  @State private var opacity: Double = 0
  
  var body: some View {
    VStack(spacing: 0) {
      contentView
    }
    .padding(.horizontal, 9)
    .frame(width: 76, height: 21)
    .background(
      RoundedRectangle(cornerRadius: 9, style: .continuous)
        .fill(Color.black)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 9, style: .continuous)
        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
    }
    .scaleEffect(scale, anchor: .top)
    .opacity(opacity)
    .onChange(of: viewModel.shouldAnimateAppearance) { _, shouldAnimate in
      applyAppearanceAnimation(shouldAnimate: shouldAnimate)
    }
    .onAppear {
      applyAppearanceAnimation(shouldAnimate: viewModel.shouldAnimateAppearance)
    }
  }

  @ViewBuilder
  private var contentView: some View {
    switch viewModel.content {
    case .listening(let level):
      ListeningWaveView(level: level)
    case .status(let message):
      Text(message)
        .font(.system(size: 9, weight: .semibold, design: .rounded))
        .lineLimit(2)
        .multilineTextAlignment(.center)
        .minimumScaleFactor(0.55)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
    }
  }

  private func applyAppearanceAnimation(shouldAnimate: Bool) {
    if shouldAnimate {
      scale = 0.01
      opacity = 0
      withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
        scale = 1
        opacity = 1
      }
    } else {
      scale = 1
      opacity = 1
    }
  }
}

private struct ListeningWaveView: View {
  let level: CGFloat

  private let barWeights: [CGFloat] = [0.55, 0.8, 1.0, 1.0, 0.8, 0.55]
  private let minHeight: CGFloat = 3
  private let maxHeight: CGFloat = 10

  var body: some View {
    HStack(spacing: 3) {
      ForEach(Array(barWeights.enumerated()), id: \.offset) { _, weight in
        Capsule(style: .continuous)
          .fill(Color.white)
          .frame(width: 2, height: barHeight(weight: weight))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .animation(.easeOut(duration: 0.08), value: level)
  }

  private func barHeight(weight: CGFloat) -> CGFloat {
    minHeight + ((maxHeight - minHeight) * level * weight)
  }
}

#Preview {
  IndicatorView(viewModel: IndicatorPanelController.ViewModel())
}
