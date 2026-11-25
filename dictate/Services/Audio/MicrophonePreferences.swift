import Foundation

extension Notification.Name {
  static let microphonePreferencesDidChange = Notification.Name("fr.lalfred.dictate.microphonePreferencesDidChange")
}

/// How the user wants the microphone to be chosen when a dictation starts.
nonisolated struct MicrophonePreferences: Codable, Equatable, Sendable {
  enum Mode: String, Codable, Sendable {
    case systemDefault
    case priorityList
  }

  struct RememberedMicrophone: Codable, Equatable, Sendable {
    let uid: String
    var name: String
  }

  var mode: Mode = .systemDefault
  /// Most preferred first. Used in `priorityList` mode.
  var priority: [RememberedMicrophone] = []
  /// In `systemDefault` mode, uses the Mac's microphone instead of a Bluetooth default input, which
  /// would switch the headphones to their lower quality call mode.
  var avoidBluetoothMicrophone = true

  /// Appends the devices not remembered yet, and refreshes the names of the others.
  func remembering(_ devices: [InputDevice]) -> MicrophonePreferences {
    var updated = self
    for device in devices {
      if let index = updated.priority.firstIndex(where: { $0.uid == device.uid }) {
        updated.priority[index].name = device.name
      } else {
        updated.priority.append(RememberedMicrophone(uid: device.uid, name: device.name))
      }
    }
    return updated
  }

  func moving(uid: String, by offset: Int) -> MicrophonePreferences {
    guard let index = priority.firstIndex(where: { $0.uid == uid }) else { return self }
    return moving(uid: uid, toIndex: index + offset)
  }

  /// Moves the microphone so it ends up at `destination` in the list, clamped to the list's bounds.
  func moving(uid: String, toIndex destination: Int) -> MicrophonePreferences {
    guard let index = priority.firstIndex(where: { $0.uid == uid }) else { return self }
    var updated = self
    let microphone = updated.priority.remove(at: index)
    updated.priority.insert(microphone, at: min(max(destination, 0), updated.priority.count))
    return updated
  }

  func removing(uid: String) -> MicrophonePreferences {
    var updated = self
    updated.priority.removeAll { $0.uid == uid }
    return updated
  }
}

struct MicrophonePreferencesStore {
  private let store: UserDefaultsCodableStore<MicrophonePreferences>

  init(defaults: UserDefaults = .standard) {
    store = UserDefaultsCodableStore(key: AppDefaultsKey.microphonePreferences, userDefaults: defaults)
  }

  func load() -> MicrophonePreferences {
    store.load() ?? MicrophonePreferences()
  }

  func save(_ preferences: MicrophonePreferences) {
    guard preferences != load() else { return }
    store.save(preferences)
    NotificationCenter.default.post(name: .microphonePreferencesDidChange, object: nil)
  }
}
