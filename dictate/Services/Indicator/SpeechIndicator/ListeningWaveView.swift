import SwiftUI

struct ListeningWaveView: View {
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
