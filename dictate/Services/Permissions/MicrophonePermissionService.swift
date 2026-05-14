import Foundation
import AVFoundation
import AppKit


struct MicrophonePermissionService {
  func authorizationStatus() -> AVAuthorizationStatus {
    AVCaptureDevice.authorizationStatus(for: .audio)
  }

  func isAuthorized() -> Bool {
    authorizationStatus() == .authorized
  }

  func requestAccess(completion: @escaping (Bool) -> Void) {
    AVCaptureDevice.requestAccess(for: .audio) { granted in
      DispatchQueue.main.async {
        completion(granted)
      }
    }
  }

  func openSystemSettings() {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else {
      return
    }
    NSWorkspace.shared.open(url)
  }
}
