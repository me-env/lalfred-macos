import SwiftUI


struct SpeechIndicatorView: View {
  let content: IndicatorPanelController.BubbleContent
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
        statusImage
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(statusForegroundColor(for: message))
          .symbolRenderingMode(.hierarchical)
          .offset(y: statusYOffset(for: message))
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        Text(message)
          .font(.system(size: 11, weight: .semibold, design: .rounded))
          .lineLimit(3)
          .multilineTextAlignment(.center)
          .minimumScaleFactor(0.8)
          .foregroundStyle(.white)
          .frame(maxWidth: textMaxWidth)
          .fixedSize(horizontal: false, vertical: true)
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

  private var textMaxWidth: CGFloat {
    220
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

  private func statusForegroundColor(for message: String) -> Color {
    switch normalizedStatusMessage(message) {
    case "cancel":
      return Color(red: 1.0, green: 0.72, blue: 0.72)
    default:
      return .white
    }
  }

  private func statusYOffset(for message: String) -> CGFloat {
    switch normalizedStatusMessage(message) {
    case "pasted":
      return -1
    default:
      return 0
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

private struct ProcessingActivityView: View {
  private let dotCount = 3
  private let cycleDuration: Double = 0.95
  private let dotDelay: Double = 0.13

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
      let time = context.date.timeIntervalSinceReferenceDate
      HStack(spacing: 3) {
        ForEach(0..<dotCount, id: \.self) { index in
          let progress = dotProgress(for: index, time: time)
          Circle()
            .fill(.white)
            .frame(width: 3.5, height: 3.5)
            .opacity(0.3 + (0.7 * progress))
            .scaleEffect(0.82 + (0.32 * progress))
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func dotProgress(for index: Int, time: TimeInterval) -> Double {
    let offsetTime = time - (Double(index) * dotDelay)
    let phase = offsetTime.truncatingRemainder(dividingBy: cycleDuration) / cycleDuration
    return 0.5 - (0.5 * cos(phase * .pi * 2))
  }
}

#Preview("Listening (Low)") {
  SpeechIndicatorView(
    content: .listening(level: 0.2),
    shouldAnimateAppearance: false
  )
  .padding()
}

#Preview("Listening (High)") {
  SpeechIndicatorView(
    content: .listening(level: 0.9),
    shouldAnimateAppearance: false
  )
  .padding()
}

#Preview("Status: Processing") {
  SpeechIndicatorView(
    content: .status(message: "processing"),
    shouldAnimateAppearance: false
  )
  .padding()
}

#Preview("Status: Cancel") {
  SpeechIndicatorView(
    content: .status(message: "cancel"),
    shouldAnimateAppearance: false
  )
  .padding()
}

#Preview("Status: Pasted") {
  SpeechIndicatorView(
    content: .status(message: "pasted"),
    shouldAnimateAppearance: false
  )
  .padding()
}

#Preview("Status: Text Fallback") {
  SpeechIndicatorView(
    content: .status(message: "Network error while processing"),
    shouldAnimateAppearance: false
  )
  .padding()
}
