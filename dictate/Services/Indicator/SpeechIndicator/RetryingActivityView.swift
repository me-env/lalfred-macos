import SwiftUI

/// The processing dots followed by "Retrying", shown while a failed transcription is sent again.
struct RetryingActivityView: View {
  var body: some View {
    HStack(spacing: 6) {
      ProcessingActivityView()
        .fixedSize()
      Text("Retrying")
        .font(.system(size: 11, weight: .semibold, design: .rounded))
        .foregroundStyle(.white)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

#Preview("Retrying") {
  RetryingActivityView()
    .frame(
      width: IndicatorPanelMetrics.retryingBubbleSize.width,
      height: IndicatorPanelMetrics.retryingBubbleSize.height
    )
    .background {
      RoundedRectangle(cornerRadius: 18, style: .continuous)
        .fill(Color.black)
        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
    }
    .padding()
}
