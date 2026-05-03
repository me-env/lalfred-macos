import SwiftUI


struct SpeechIndicatorView: View {
  let content: IndicatorBubbleContent
  let shouldAnimateAppearance: Bool
  
  @State private var scale: CGFloat = 0.01
  @State private var opacity: Double = 0
  @State private var contentScale: CGFloat = 1
  @State private var contentBounceTask: Task<Void, Never>?
  
  var body: some View {
    VStack(spacing: 0) {
      contentView
    }
    .padding(.horizontal, horizontalPadding)
    .padding(.vertical, verticalPadding)
    .frame(minWidth: contentMinWidth, minHeight: contentMinHeight)
    .scaleEffect(scale * contentScale, anchor: .top)
    .opacity(opacity)
    .onChange(of: shouldAnimateAppearance) { _, shouldAnimate in
      applyAppearanceAnimation(shouldAnimate: shouldAnimate)
    }
    .onChange(of: contentBounceKey) { _, _ in
      applyContentBounceAnimationIfNeeded()
    }
    .onAppear {
      applyAppearanceAnimation(shouldAnimate: shouldAnimateAppearance)
    }
  }
  
  @ViewBuilder
  private var contentView: some View {
    switch content {
    case .listening(let level):
      ListeningWaveView(level: level)
    case .status(let message):
      if isProcessingStatus(message) {
        ProcessingActivityView()
      } else if let statusImage = statusImage(for: message) {
        StatusImageView(statusImage: statusImage, message: message)
      } else {
        StatusTextView(message: message)
      }
    }
  }
  
  private var horizontalPadding: CGFloat {
    prefersExpandedTextLayout ? 12 : 9
  }

  private var verticalPadding: CGFloat {
    prefersExpandedTextLayout ? 8 : 0
  }

  private var contentMinWidth: CGFloat {
    prefersExpandedTextLayout ? 120 : 54
  }

  private var contentMinHeight: CGFloat {
    prefersExpandedTextLayout ? 34 : 21
  }

  private var prefersExpandedTextLayout: Bool {
    switch content {
    case .listening:
      return false
    case .status(let message):
      return statusImage(for: message) == nil && !isProcessingStatus(message)
    }
  }

  private func statusImage(for message: String) -> Image? {
    switch normalizedStatusMessage(message) {
    case "cancel":
      return Image(systemName: "xmark")
    case "pasted":
      return Image(systemName: "clipboard.fill")
    case "nospeech":
      return Image(systemName: "mic.slash")
    default:
      return nil
    }
  }

  private func isProcessingStatus(_ message: String) -> Bool {
    normalizedStatusMessage(message) == "processing"
  }

  private func normalizedStatusMessage(_ message: String) -> String {
    message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }
  
  private var contentBounceKey: String {
    switch content {
    case .listening:
      return "listening"
    case .status(let message):
      return "status:\(message)"
    }
  }
  
  private func applyAppearanceAnimation(shouldAnimate: Bool) {
    if shouldAnimate {
      scale = 0.84
      opacity = 0
      withAnimation(.spring(response: 0.22, dampingFraction: 0.62, blendDuration: 0.04)) {
        scale = 1
        opacity = 1
      }
    } else {
      scale = 1
      opacity = 1
    }
  }
  
  private func applyContentBounceAnimationIfNeeded() {
    guard !shouldAnimateAppearance else { return }

    contentBounceTask?.cancel()
    contentScale = 1

    guard case .listening = content else {
      withAnimation(.default) {
        contentScale = 1
      }
      return
    }

    withAnimation(.easeOut(duration: 0.08)) {
      contentScale = 0.94
    }

    contentBounceTask = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(75))
      guard !Task.isCancelled else { return }
      withAnimation(.spring(response: 0.22, dampingFraction: 0.78, blendDuration: 0.04)) {
        contentScale = 1
      }
    }
  }
}

