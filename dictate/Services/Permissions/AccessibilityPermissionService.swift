import Foundation
import ApplicationServices
import AppKit


struct AccessibilityPermissionService {
  func isTrusted() -> Bool {
    return AXIsProcessTrusted()
  }
  
  func requestPrompt() -> Bool {
    let options = [
      kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true
    ] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
  }
}
