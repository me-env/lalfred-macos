//
//  Design notes:
//  - One shared instance, lazy-loaded NSSound objects, cached per resource.
//  - Reads the user's choice via SoundEffectDefaultsStore on each call,
//    so changes from the Sounds tab take effect instantly.
//  - For preview-from-settings we want consecutive presses to *retrigger*
//    the sound, not be ignored mid-playback. NSSound's `play()` returns
//    false if the sound is already playing, so we stop-and-restart.
//

import AppKit
import OSLog

 
private let logger = Logger(subsystem: "fr.lalfred.dictate", category: "SoundEffectPlayer")


@MainActor
final class SoundEffectPlayer {
  static let shared = SoundEffectPlayer()

  private let store = SoundEffectDefaultsStore()
  private var cache: [String: NSSound] = [:]
  private var changeObserver: NSObjectProtocol?

  private init() {
    store.ensureDefault()
    changeObserver = NotificationCenter.default.addObserver(
      forName: .soundEffectKindDidChange,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      // Drop cached sounds so the next play uses freshly-resolved resources.
      Task { @MainActor in
        self?.cache.removeAll()
      }
    }
  }

  deinit {
    if let changeObserver {
      NotificationCenter.default.removeObserver(changeObserver)
    }
  }

  // MARK: - Public API

  func playStart() {
    play(resource: store.load().startResource)
  }

  func playStop() {
    play(resource: store.load().stopResource)
  }

  func previewStart(of kind: SoundEffectKind) {
    play(resource: kind.startResource)
  }

  func previewStop(of kind: SoundEffectKind) {
    play(resource: kind.stopResource)
  }

  // MARK: - Internal

  private func play(resource: String?) {
    guard let resource else { return }  // .none → silent

    guard let sound = sound(forResource: resource) else {
      logger.error("Missing bundled sound resource: \(resource, privacy: .public)")
      return
    }

    // If it's already mid-playback (rapid presses), stop and replay so the
    // user gets immediate feedback rather than a no-op.
    if sound.isPlaying { sound.stop() }
    sound.volume = 0.35
    sound.play()
  }

  private func sound(forResource name: String) -> NSSound? {
    if let cached = cache[name] { return cached }

    // We bundle WAVs explicitly. Falling back to NSSound(named:) would only
    // work if the file lived at the bundle root, which it doesn't.
    guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else {
      return nil
    }
    guard let sound = NSSound(contentsOf: url, byReference: true) else {
      return nil
    }

    cache[name] = sound
    return sound
  }
}
