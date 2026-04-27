//
//  PermissionsInput.swift
//  dictate
//
//  Created by Codex on 4/26/26.
//

import SwiftUI
import AVFoundation
import AppKit

struct PermissionsInput: View {
  @Environment(\.scenePhase) private var scenePhase

  private let accessibilityPermissionService = AccessibilityPermissionService()

  @State private var microphoneGranted: Bool = false
  @State private var accessibilityGranted: Bool = false
  
  var body: some View {
    SectionBox("Permissions", caption: "Accessibility is required for global shortcut handling and paste into other apps.") {
      permissionRow(
        title: "Microphone",
        granted: microphoneGranted,
        buttonTitle: microphoneGranted ? "Granted" : "Request"
      ) {
        requestMicrophonePermission()
      }

      permissionRow(
        title: "Accessibility",
        granted: accessibilityGranted,
        buttonTitle: accessibilityGranted ? "Granted" : "Request"
      ) {
        requestAccessibilityPermission()
      }
    }
    .onAppear {
      refreshStatuses()
    }
    .onChange(of: scenePhase) { _, newPhase in
      if newPhase == .active {
        refreshStatuses()
      }
    }
  }
  
  @ViewBuilder
  private func permissionRow(
    title: String,
    granted: Bool,
    buttonTitle: String,
    action: @escaping () -> Void
  ) -> some View {
    HStack {
      Text(title)
      Spacer()
      Text(granted ? "Granted" : "Not granted")
        .font(.caption)
        .foregroundStyle(granted ? .green : .secondary)
      Button(buttonTitle, action: action)
        .disabled(granted)
    }
  }
  
  private func refreshStatuses() {
    microphoneGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    accessibilityGranted = accessibilityPermissionService.isTrusted()
    print("[PermissionsInput] refreshStatuses accessibilityGranted=\(accessibilityGranted)")
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
    print("[PermissionsInput] requestAccessibilityPermission immediate result=\(accessibilityGranted)")

    // The trust prompt and Settings grant are asynchronous, refresh shortly after.
    Task {
      try? await Task.sleep(for: .seconds(0.8))
      refreshStatuses()

      if !accessibilityGranted {
        accessibilityPermissionService.openSettings()
      }
    }
  }
}

#Preview {
  PermissionsInput()
    .padding()
}
