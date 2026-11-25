import Foundation

/// Maps levels in dBFS to 0...1 relative to the microphone's own noise floor and recent speech peak,
/// so normal speech fills the meter whatever the mic's gain, while room noise stays flat.
nonisolated struct SpeechLevelNormalizer {
  /// Gaps between words pull the floor down quickly; steady noise raises it slowly.
  static let floorFallSeconds: Float = 0.25
  static let floorRiseSeconds: Float = 4
  /// Above this, the level is speech, not noise, whatever the floor did.
  static let maximumFloorDecibels: Float = -35
  /// Voice starts this far above the floor; anything below reads as silence.
  static let voiceThresholdDecibels: Float = 8
  /// The peak never gets this close to the floor, so faint noise is never stretched to full bars.
  static let minimumSpanDecibels: Float = 20
  /// After a loud burst, the peak holds, then decays so normal speech fills the range again.
  static let peakHoldSeconds: Float = 1
  static let peakDecayDecibelsPerSecond: Float = 8
  /// Below 1, lifts mid levels so a normal syllable moves the bars clearly.
  static let curveExponent: Float = 0.75
  /// A gap in reports longer than this is treated as this long, e.g. the very first report.
  static let maximumElapsedSeconds: Float = 0.1
  static let silenceDecibels: Float = -100

  private var floorDecibels: Float?
  private var peakDecibels: Float = silenceDecibels
  private var secondsSincePeak: Float = 0

  /// 0 for silence and noise, 1 at the recent speech peak.
  mutating func level(for decibels: Float, elapsedSeconds: Float) -> Float {
    let decibels = Self.sanitized(decibels)
    let elapsed = Self.sanitizedElapsed(elapsedSeconds)
    let floor = updatedFloor(with: decibels, elapsed: elapsed)
    let voiceStart = floor + Self.voiceThresholdDecibels
    let peak = updatedPeak(with: decibels, voiceStart: voiceStart, floor: floor, elapsed: elapsed)
    guard decibels > voiceStart else { return 0 }

    let position = min((decibels - voiceStart) / (peak - voiceStart), 1)
    return pow(position, Self.curveExponent)
  }

  private mutating func updatedFloor(with decibels: Float, elapsed: Float) -> Float {
    let floor = min(Self.smoothedFloor(from: floorDecibels, toward: decibels, elapsed: elapsed), Self.maximumFloorDecibels)
    floorDecibels = floor
    return floor
  }

  /// Rises at once with voice; past the hold, decays down to the minimum span above the floor.
  private mutating func updatedPeak(with decibels: Float, voiceStart: Float, floor: Float, elapsed: Float) -> Float {
    let lowestPeak = floor + Self.minimumSpanDecibels
    if decibels > voiceStart, decibels >= peakDecibels {
      peakDecibels = decibels
      secondsSincePeak = 0
    } else {
      secondsSincePeak += elapsed
      let decayingSeconds = min(secondsSincePeak - Self.peakHoldSeconds, elapsed)
      if decayingSeconds > 0 {
        peakDecibels -= Self.peakDecayDecibelsPerSecond * decayingSeconds
      }
    }
    peakDecibels = max(peakDecibels, lowestPeak)
    return peakDecibels
  }

  /// The first level sets the floor; later ones move it, faster downward than upward.
  private static func smoothedFloor(from previous: Float?, toward decibels: Float, elapsed: Float) -> Float {
    guard let previous else { return decibels }
    let timeConstant = decibels < previous ? floorFallSeconds : floorRiseSeconds
    return previous + (decibels - previous) * smoothingFactor(elapsed: elapsed, timeConstant: timeConstant)
  }

  private static func smoothingFactor(elapsed: Float, timeConstant: Float) -> Float {
    1 - exp(-elapsed / timeConstant)
  }

  private static func sanitized(_ decibels: Float) -> Float {
    guard !decibels.isNaN else { return silenceDecibels }
    return min(max(decibels, silenceDecibels), 0)
  }

  private static func sanitizedElapsed(_ seconds: Float) -> Float {
    guard seconds.isFinite, seconds > 0 else { return 0 }
    return min(seconds, maximumElapsedSeconds)
  }
}
