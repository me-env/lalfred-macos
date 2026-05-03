import Foundation

enum SoundEffectKind: String, CaseIterable, Identifiable, Hashable {
  case none
  case pure
  case duet
  case bell
  case warm

  var id: String { rawValue }

  /// Human-facing name shown in the Sounds tab.
  var displayName: String {
    switch self {
    case .none: return "None"
    case .pure: return "Pure"
    case .duet: return "Duet"
    case .bell: return "Bell"
    case .warm: return "Warm"
    }
  }

  /// Short description shown beneath each option.
  var detail: String {
    switch self {
    case .none:
      return "Silent. No sound when recording starts or stops."
    case .pure:
      return "A single soft sine tone. The most minimal option."
    case .duet:
      return "Two notes, a quick perfect-fifth interval. Discreet and musical."
    case .bell:
      return "A gentle bell-like ping with natural decay."
    case .warm:
      return "A lower, woodier triangle tone. Almost felt rather than heard."
    }
  }

  /// Resource name (without extension) for the start sound, or nil for `.none`.
  var startResource: String? {
    switch self {
    case .none: return nil
    case .pure: return "A_pure_start"
    case .duet: return "B_duet_start"
    case .bell: return "C_bell_start"
    case .warm: return "D_warm_start"
    }
  }

  /// Resource name (without extension) for the stop sound, or nil for `.none`.
  var stopResource: String? {
    switch self {
    case .none: return nil
    case .pure: return "A_pure_stop"
    case .duet: return "B_duet_stop"
    case .bell: return "C_bell_stop"
    case .warm: return "D_warm_stop"
    }
  }

  /// Default pack used on first launch.
  static let defaultKind: SoundEffectKind = .duet
}
