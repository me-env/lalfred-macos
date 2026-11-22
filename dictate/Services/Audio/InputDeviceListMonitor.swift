import Foundation
import CoreAudio

extension Notification.Name {
  static let audioDevicesDidChange = Notification.Name("fr.lalfred.dictate.audioDevicesDidChange")
}

/// Posts `audioDevicesDidChange` on the main thread when a device connects or disconnects.
nonisolated enum InputDeviceListMonitor {
  /// Registered once for the app's lifetime, like `AudioDeviceChangeObserver`'s listeners.
  private static let registration: Void = {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { _, _ in
      NotificationCenter.default.post(name: .audioDevicesDidChange, object: nil)
    }
  }()

  static func start() {
    _ = registration
  }
}
