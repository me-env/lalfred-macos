import Foundation
import Observation

@Observable
final class ShortcutStore {
  let key: String
  private(set) var shortcut: Shortcut?

  @ObservationIgnored private let codableStore: UserDefaultsCodableStore<Shortcut>
  @ObservationIgnored private let userDefaults: UserDefaults = .standard
  @ObservationIgnored private let disabledKey: String

  init(key: String) {
    self.key = key
    self.disabledKey = "\(key).disabled"
    self.codableStore = UserDefaultsCodableStore<Shortcut>(key: key, userDefaults: userDefaults)
    self.shortcut = userDefaults.bool(forKey: disabledKey) ? nil : codableStore.load()
  }

  func save(_ newShortcut: Shortcut) {
    userDefaults.set(false, forKey: disabledKey)
    codableStore.save(newShortcut)
    shortcut = newShortcut
  }

  func remove() {
    userDefaults.set(true, forKey: disabledKey)
    codableStore.remove()
    shortcut = nil
  }

  func ensureDefault(_ defaultShortcut: Shortcut) {
    guard !isDisabled, codableStore.load() == nil else { return }
    codableStore.save(defaultShortcut)
    shortcut = defaultShortcut
  }

  private var isDisabled: Bool {
    userDefaults.bool(forKey: disabledKey)
  }
}
