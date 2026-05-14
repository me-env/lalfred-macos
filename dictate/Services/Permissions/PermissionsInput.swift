import SwiftUI
import AVFoundation
import AppKit
import os


private let logger = Logger(subsystem: "fr.lalfred.dictate", category: "PermissionsInput")


struct PermissionsInput: View {
  private let configuration = AppConfigurationModel.shared
  private let microphonePermissionService = MicrophonePermissionService()
  private let accessibilityPermissionService = AccessibilityPermissionService()

  var body: some View {
    PermissionsView(
      microphoneGranted: configuration.microphoneGranted,
      accessibilityGranted: configuration.accessibilityGranted,
      requestMicrophonePermission: requestMicrophonePermission,
      requestAccessibilityPermission: requestAccessibilityPermission
    )
  }

  private func requestMicrophonePermission() {
    switch microphonePermissionService.authorizationStatus() {
    case .authorized:
      configuration.refresh()
    case .notDetermined:
      microphonePermissionService.requestAccess { granted in
        logger.info("microphone requestAccess granted=\(granted)")
        configuration.refresh()
      }
    case .denied, .restricted:
      microphonePermissionService.openSystemSettings()
      configuration.refresh()
    @unknown default:
      configuration.refresh()
    }
  }

  private func requestAccessibilityPermission() {
    // Returns the *current* trust value; the actual grant happens later in
    // System Settings, picked up via `NSApplication.didBecomeActiveNotification`
    // observed by ``AppConfigurationModel``.
    _ = accessibilityPermissionService.requestPrompt()
    configuration.refresh()
  }
}

private struct PermissionsView: View {
  let microphoneGranted: Bool
  let accessibilityGranted: Bool
  let requestMicrophonePermission: () -> Void
  let requestAccessibilityPermission: () -> Void
  
  var body: some View {
    SectionBoxWithTitle(
      "Permissions",
      caption: "Accessibility is required to paste text from transcription into other apps."
    ) {
      PermissionRow(
        icon: microphoneGranted ? "microphone" : "microphone.slash",
        title: "Microphone",
        granted: microphoneGranted,
        action: requestMicrophonePermission
      )
      
      PermissionRow(
        icon: "accessibility",
        title: "Accessibility",
        granted: accessibilityGranted,
        action: requestAccessibilityPermission
      )
    }
  }
}
  
private struct PermissionRow: View {
  let icon: String
  let title: String
  let granted: Bool
  let action: () -> Void

  var body: some View {
    HStack {
      Image(systemName: icon)
        .frame(width: 24)
        .foregroundStyle(granted ? Color.iconDefault : Color.red)
      

      Text(title)
      Spacer()

      if !granted {
        Button(action: action) {
          Text("Request")
        }
      } else {
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(Color.green)
      }
    }
    .frame(height: 24)
  }
}

#Preview("Permissions Granted") {
  PermissionsView(
    microphoneGranted: true,
    accessibilityGranted: true,
    requestMicrophonePermission: {},
    requestAccessibilityPermission: {}
  )
  .padding()
}

#Preview("Permissions Not Granted") {
  PermissionsView(
    microphoneGranted: false,
    accessibilityGranted: false,
    requestMicrophonePermission: {},
    requestAccessibilityPermission: {}
  )
  .padding()
}
