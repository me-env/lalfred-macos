import Foundation
import Observation
import AppKit
import os


private let logger = Logger(subsystem: "fr.lalfred.dictate", category: "AppConfigurationModel")


/// Single source of truth for "is the user fully set up?" — the microphone
/// and accessibility permissions. Signing in is optional and deliberately not
/// part of this.
///
/// macOS exposes no notification for permission changes (`AXIsProcessTrusted`
/// is a pure query and `AVCaptureDevice` only signals via the per-call
/// `requestAccess` completion handler), so we refresh on:
///
/// * `NSApplication.didBecomeActiveNotification` — covers System Settings
///   round trips for accessibility and any TCC prompt that briefly resigns
///   active state.
/// * Explicit ``refresh()`` calls from ``PermissionsInput`` after an inline
///   `requestAccess` completion, where the active state may not change.
@MainActor
@Observable
final class AppConfigurationModel {
  static let shared = AppConfigurationModel()

  private(set) var microphoneGranted: Bool = false
  private(set) var accessibilityGranted: Bool = false

  var isFullyConfigured: Bool {
    microphoneGranted && accessibilityGranted
  }

  private let microphonePermissionService = MicrophonePermissionService()
  private let accessibilityPermissionService = AccessibilityPermissionService()

  private init() {
    refresh()

    // Singleton: lives for the app's lifetime, so we don't bother tearing
    // this observer down. The `[weak self]` is therefore strictly defensive.
    NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.refresh()
      }
    }
  }

  func refresh() {
    let micGranted = microphonePermissionService.isAuthorized()
    let axGranted = accessibilityPermissionService.isTrusted()

    logger.info("micGranted=\(micGranted) axGranted=\(axGranted)")
    if microphoneGranted != micGranted { microphoneGranted = micGranted }
    if accessibilityGranted != axGranted { accessibilityGranted = axGranted }
  }
}
