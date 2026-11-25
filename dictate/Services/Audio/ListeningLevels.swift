/// How strongly each voice band is heard, from the lowest band to the highest, each in 0...1.
nonisolated struct ListeningLevels: Equatable, Sendable {
  static let bandCount = 6
  static let silent = ListeningLevels(clamping: .zero)

  /// Only the first `bandCount` lanes are used; the others stay 0.
  private let lanes: SIMD8<Float>

  /// NaN reads as 0; lanes past `bandCount` are ignored.
  init(clamping lanes: SIMD8<Float>) {
    let usedLanes = SIMD8<Float>(1, 1, 1, 1, 1, 1, 0, 0)
    let numbers = lanes.replacing(with: 0, where: lanes .!= lanes)
    self.lanes = numbers.clamped(lowerBound: .zero, upperBound: .one) * usedLanes
  }

  subscript(band: Int) -> Float {
    lanes[band]
  }
}
