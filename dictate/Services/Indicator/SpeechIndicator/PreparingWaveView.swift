import SwiftUI

/// Shown while the microphone delivers no audio yet, e.g. a Bluetooth headset switching to its mic mode.
/// Same bars as `ListeningWaveView`, flat and dimmed, so the switch to listening reads as "now live".
struct PreparingWaveView: View {
  private let barCount = 6
  private let cycleDuration: Double = 1.1
  private let barDelay: Double = 0.09

  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
      let time = context.date.timeIntervalSinceReferenceDate
      HStack(spacing: 3) {
        ForEach(0..<barCount, id: \.self) { index in
          Capsule(style: .continuous)
            .fill(Color.white)
            .frame(width: 2, height: 3)
            .opacity(0.25 + (0.45 * barProgress(for: index, time: time)))
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func barProgress(for index: Int, time: TimeInterval) -> Double {
    let offsetTime = time - (Double(index) * barDelay)
    let phase = offsetTime.truncatingRemainder(dividingBy: cycleDuration) / cycleDuration
    return 0.5 - (0.5 * cos(phase * .pi * 2))
  }
}
