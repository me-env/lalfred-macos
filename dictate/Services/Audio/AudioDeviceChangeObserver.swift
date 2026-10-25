import Foundation
import CoreAudio

/// Reports changes of the default input device, and of the sample rate or input format of every
/// input device used so far.
///
/// Listeners stay registered for the app's lifetime: CoreAudio keeps a listener block, and everything
/// it captures, even after `AudioObjectRemovePropertyListenerBlock` succeeds, so removing them per
/// recording leaked every recording's capture session and audio.
final class AudioDeviceChangeObserver {
  private let queue: DispatchQueue
  /// Called on `queue`; several properties often change together.
  private let onChange: @Sendable () -> Void
  private var observedObjects: Set<AudioObjectID> = []

  init(queue: DispatchQueue, onChange: @escaping @Sendable () -> Void) {
    self.queue = queue
    self.onChange = onChange
  }

  func observe(inputDevice: AudioDeviceID) {
    let system = AudioObjectID(kAudioObjectSystemObject)
    if !observedObjects.contains(system),
       addListener(system, kAudioHardwarePropertyDefaultInputDevice) {
      observedObjects.insert(system)
    }
    if !observedObjects.contains(inputDevice),
       addListener(inputDevice, kAudioDevicePropertyNominalSampleRate),
       addListener(inputDevice, kAudioDevicePropertyStreamConfiguration, scope: kAudioObjectPropertyScopeInput) {
      observedObjects.insert(inputDevice)
    }
  }

  /// Returns whether the listener was registered.
  private func addListener(
    _ objectID: AudioObjectID,
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
  ) -> Bool {
    var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    return AudioObjectAddPropertyListenerBlock(objectID, &address, queue, Self.makeListenerBlock(onChange)) == noErr
  }

  private nonisolated static func makeListenerBlock(_ onChange: @escaping @Sendable () -> Void) -> AudioObjectPropertyListenerBlock {
    { _, _ in onChange() }
  }
}
