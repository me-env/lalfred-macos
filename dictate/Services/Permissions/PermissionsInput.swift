import SwiftUI
import AVFoundation
import AppKit

struct PermissionsInput: View {
  @Environment(\.scenePhase) private var scenePhase

  private let accessibilityPermissionService = AccessibilityPermissionService()

  @State private var microphoneGranted: Bool = false
  @State private var accessibilityGranted: Bool = false
  
  var body: some View {
    PermissionsView(
      microphoneGranted: microphoneGranted,
      accessibilityGranted: accessibilityGranted,
      requestMicrophonePermission: requestMicrophonePermission,
      requestAccessibilityPermission: requestAccessibilityPermission
    )
    .onAppear {
      refreshStatuses()
    }
    .onChange(of: scenePhase) { _, newPhase in
      if newPhase == .active {
        refreshStatusesIfNeeded()
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
      refreshStatusesIfNeeded()
    }
  }

  private var hasMissingPermission: Bool {
    !microphoneGranted || !accessibilityGranted
  }
  
  private func refreshStatuses() {
    microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    accessibilityGranted = accessibilityPermissionService.isTrusted()
    print("[PermissionsInput] refreshStatuses accessibilityGranted=\(accessibilityGranted)")
  }

  private func refreshStatusesIfNeeded() {
    guard hasMissingPermission else { return }
    refreshStatuses()
  }
  
  private func requestMicrophonePermission() {
    let status = AVCaptureDevice.authorizationStatus(for: .audio)
    
    switch status {
    case .authorized:
      microphoneGranted = true
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .audio) { granted in
        DispatchQueue.main.async {
          microphoneGranted = granted
        }
      }
    case .denied, .restricted:
      microphoneGranted = false
      if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
        NSWorkspace.shared.open(settingsURL)
      }
    @unknown default:
      microphoneGranted = false
    }
  }
  
  private func requestAccessibilityPermission() {
    accessibilityGranted = accessibilityPermissionService.requestPrompt()
    refreshStatuses()
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

