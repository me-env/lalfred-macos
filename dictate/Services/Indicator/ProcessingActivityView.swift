import SwiftUI

struct ProcessingActivityView: View {
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
