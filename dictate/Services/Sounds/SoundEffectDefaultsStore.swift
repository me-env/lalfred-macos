import Foundation


extension Notification.Name {
  static let soundEffectKindDidChange = Notification.Name("fr.lalfred.dictate.soundEffectKindDidChange")
}


struct SoundEffectDefaultsStore {
  private let defaults: UserDefaults
  private let key: String

  init(defaults: UserDefaults = .standard, key: String = AppDefaultsKey.soundEffectKind) {
    self.defaults = defaults
    self.key = key
  }

  /// Reads the persisted kind, falling back to the default on first launch
  /// or if the stored value is unrecognised.
  func load() -> SoundEffectKind {
    guard let rawValue = defaults.string(forKey: key),
          let kind = SoundEffectKind(rawValue: rawValue) else {
      return .defaultKind
    }
    return kind
  }

  /// Persists the new kind and notifies observers if the value actually changed.
  func save(_ kind: SoundEffectKind) {
    let previous = defaults.string(forKey: key)
    guard previous != kind.rawValue else { return }
    defaults.set(kind.rawValue, forKey: key)
    NotificationCenter.default.post(name: .soundEffectKindDidChange, object: nil)
  }

  /// Writes the default value if nothing is stored yet, so the very first
  /// recording in a fresh install plays the duet pack as agreed.
  func ensureDefault() {
    guard defaults.string(forKey: key) == nil else { return }
    defaults.set(SoundEffectKind.defaultKind.rawValue, forKey: key)
  }
}
