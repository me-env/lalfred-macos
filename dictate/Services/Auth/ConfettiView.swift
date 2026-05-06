import SwiftUI

/// Self-contained confetti animation. Drops paper-like rectangles from the top
/// of its bounds with random velocity, rotation and colour. Stops on its own
/// after `duration` so it doesn't keep burning CPU forever.
struct ConfettiView: View {
  var pieceCount: Int = 90
  var duration: Double = 2.6

  @State private var pieces: [Piece] = []
  @State private var startedAt: Date?

  var body: some View {
    GeometryReader { geometry in
      TimelineView(.animation) { context in
        Canvas { canvasContext, size in
          guard let startedAt else { return }
          let elapsed = context.date.timeIntervalSince(startedAt)
          guard elapsed < duration else { return }
          drawPieces(in: canvasContext, size: size, elapsed: elapsed)
        }
      }
      .onAppear {
        if pieces.isEmpty {
          pieces = Self.makePieces(count: pieceCount, width: geometry.size.width)
        }
        startedAt = Date()
      }
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private func drawPieces(in context: GraphicsContext, size: CGSize, elapsed: Double) {
    let progress = min(elapsed / duration, 1)
    let fadeOut = max(0, 1 - pow(progress, 3))

    for piece in pieces {
      let t = elapsed
      let x = piece.startX * size.width + piece.driftAmplitude * sin(t * piece.driftFrequency + piece.phase)
      let fallDistance = piece.gravity * t * t * 0.5 + piece.initialVelocityY * t
      let y = piece.startY + fallDistance
      guard y < size.height + 40 else { continue }

      let rotation = piece.rotationStart + piece.rotationSpeed * t
      let rect = CGRect(x: -piece.size.width / 2, y: -piece.size.height / 2,
                        width: piece.size.width, height: piece.size.height)

      var pieceContext = context
      pieceContext.translateBy(x: x, y: y)
      pieceContext.rotate(by: .radians(rotation))
      pieceContext.opacity = fadeOut
      pieceContext.fill(Path(roundedRect: rect, cornerRadius: 1.5),
                        with: .color(piece.color))
    }
  }

  // MARK: - Piece generation

  private struct Piece {
    let color: Color
    let size: CGSize
    let startX: CGFloat
    let startY: CGFloat
    let initialVelocityY: CGFloat
    let gravity: CGFloat
    let driftAmplitude: CGFloat
    let driftFrequency: Double
    let phase: Double
    let rotationStart: Double
    let rotationSpeed: Double
  }

  private static let palette: [Color] = [
    Color(red: 0.99, green: 0.78, blue: 0.27),  // amber
    Color(red: 0.31, green: 0.74, blue: 0.50),  // emerald
    Color(red: 0.36, green: 0.55, blue: 0.99),  // blue
    Color(red: 0.93, green: 0.43, blue: 0.55),  // rose
    Color(red: 0.69, green: 0.50, blue: 0.96),  // violet
  ]

  private static func makePieces(count: Int, width _: CGFloat) -> [Piece] {
    (0..<count).map { _ in
      Piece(
        color: palette.randomElement() ?? .accentColor,
        size: CGSize(
          width: CGFloat.random(in: 6...11),
          height: CGFloat.random(in: 9...16),
        ),
        startX: CGFloat.random(in: 0.05...0.95),
        startY: CGFloat.random(in: -40...0),
        initialVelocityY: CGFloat.random(in: 60...140),
        gravity: CGFloat.random(in: 320...460),
        driftAmplitude: CGFloat.random(in: 12...32),
        driftFrequency: Double.random(in: 1.4...3.0),
        phase: Double.random(in: 0...(.pi * 2)),
        rotationStart: Double.random(in: 0...(.pi * 2)),
        rotationSpeed: Double.random(in: -4.5...4.5),
      )
    }
  }
}

#Preview("Confetti") {
  ConfettiView()
    .frame(width: 360, height: 240)
    .background(Color.black.opacity(0.04))
}
