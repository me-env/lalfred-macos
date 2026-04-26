//
//  PermissionsInput.swift
//  dictate
//
//  Created by Codex on 4/26/26.
//

import SwiftUI
import AVFoundation
import ApplicationServices
import AppKit

struct PermissionsInput: View {
  @State private var microphoneGranted: Bool = false
  @State private var accessibilityGranted: Bool = false
  
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Permissions")
        .font(.headline)
      
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
      
      Text("Accessibility is required for global shortcut handling and paste into other apps.")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(
      .quaternary.opacity(0.2),
      in: RoundedRectangle(cornerRadius: 10, style: .continuous)
    )
    .onAppear {
      refreshStatuses()
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
    accessibilityGranted = AXIsProcessTrusted()
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
    let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
    accessibilityGranted = AXIsProcessTrustedWithOptions(options)
    
    if !accessibilityGranted,
       let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
      NSWorkspace.shared.open(settingsURL)
    }
  }
}

#Preview {
  PermissionsInput()
    .padding()
}
