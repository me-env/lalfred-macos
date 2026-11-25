import SwiftUI

/// One bar per voice band, lowest frequencies on the left.
struct ListeningWaveView: View {
  let levels: ListeningLevels

  private let minHeight: CGFloat = 3
  private let maxHeight: CGFloat = 13

  var body: some View {
    HStack(spacing: 3) {
      ForEach(0..<ListeningLevels.bandCount, id: \.self) { band in
        Capsule(style: .continuous)
          .fill(Color.white)
          .frame(width: 2, height: barHeight(for: band))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .animation(.easeOut(duration: 0.08), value: levels)
  }

  private func barHeight(for band: Int) -> CGFloat {
    minHeight + ((maxHeight - minHeight) * CGFloat(levels[band]))
  }
}
