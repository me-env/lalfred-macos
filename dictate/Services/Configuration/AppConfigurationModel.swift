import Foundation
import Observation
import AppKit
import os


private let logger = Logger(subsystem: "fr.lalfred.dictate", category: "AppConfigurationModel")


/// Single source of truth for "is the user fully set up?". Combines auth
/// state with the microphone and accessibility permissions.
///
/// macOS exposes no notification for permission changes (`AXIsProcessTrusted`
/// is a pure query and `AVCaptureDevice` only signals via the per-call
/// `requestAccess` completion handler), so we refresh on:
///
/// * `NSApplication.didBecomeActiveNotification` — covers System Settings
///   round trips for accessibility and any TCC prompt that briefly resigns
///   active state.
/// * `Notification.Name.appAuthStateDidChange` — posted by ``AuthManager``
///   on token mutations, so OAuth deep-link callbacks update us deterministically.
/// * Explicit ``refresh()`` calls from ``PermissionsInput`` after an inline
///   `requestAccess` completion, where the active state may not change.
@MainActor
@Observable
final class AppConfigurationModel {
  static let shared = AppConfigurationModel()

  private(set) var isSignedIn: Bool = false
  private(set) var microphoneGranted: Bool = false
  private(set) var accessibilityGranted: Bool = false

  var isFullyConfigured: Bool {
    isSignedIn && microphoneGranted && accessibilityGranted
  }

  private let microphonePermissionService = MicrophonePermissionService()
  private let accessibilityPermissionService = AccessibilityPermissionService()

  private init() {
    refresh()

    // Singleton: lives for the app's lifetime, so we don't bother tearing
    // these observers down. The `[weak self]` is therefore strictly defensive.
    let center = NotificationCenter.default

    center.addObserver(
      forName: NSApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.refresh()
      }
    }

    center.addObserver(
      forName: .appAuthStateDidChange,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.refresh()
      }
    }
  }

  func refresh() {
    let signedIn = AuthManager.shared.authToken() != nil
    let micGranted = microphonePermissionService.isAuthorized()
    let axGranted = accessibilityPermissionService.isTrusted()

    logger.info("signedIn=\(signedIn) micGranted=\(micGranted) axGranted=\(axGranted)")
    if isSignedIn != signedIn { isSignedIn = signedIn }
    if microphoneGranted != micGranted { microphoneGranted = micGranted }
    if accessibilityGranted != axGranted { accessibilityGranted = axGranted }
  }
}
