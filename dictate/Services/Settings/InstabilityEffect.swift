import SwiftUI


/// Makes a view look unstable, like a signal about to change: dimmed, slightly blurred, with
/// TV static over it and a small jitter. Only dims when the user asked for reduced motion.
struct InstabilityEffect: ViewModifier {
  let isActive: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    let moves = isActive && !reduceMotion
    TimelineView(.animation(minimumInterval: 1.0 / 14, paused: !moves)) { _ in
      content
        .opacity(isActive ? 0.55 : 1)
        .blur(radius: moves ? 0.7 : 0)
        .overlay {
          if moves {
            StaticNoise()
              .allowsHitTesting(false)
              .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          }
        }
        .offset(x: moves ? .random(in: -1.5...1.5) : 0)
    }
    .animation(.easeInOut(duration: 0.2), value: isActive)
  }
}


/// Random grey dots redrawn a few times a second: the "snow" of a TV without signal.
private struct StaticNoise: View {
  var body: some View {
    TimelineView(.animation(minimumInterval: 1.0 / 20)) { _ in
      Canvas { context, size in
        let count = Int(size.width * size.height / 160)
        for _ in 0..<count {
          let dot = CGRect(
            x: .random(in: 0..<size.width),
            y: .random(in: 0..<size.height),
            width: 1.5,
            height: 1.5
          )
          context.fill(Path(dot), with: .color(.primary.opacity(.random(in: 0.08...0.3))))
        }
      }
    }
  }
}


extension View {
  func instability(_ isActive: Bool) -> some View {
    modifier(InstabilityEffect(isActive: isActive))
  }
}
