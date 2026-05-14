import SwiftUI
import AVFoundation
import os


private let logger = Logger(subsystem: "fr.lalfred.dictate", category: "PermissionRegressionBanner")


/// Post-onboarding recovery surface for system permissions the user has
/// already granted at least once and subsequently revoked.
///
/// Designed to be mounted globally inside ``TabsView`` (above the tab
/// content), so a regression is visible regardless of which tab the user is
/// on. The banner is intentionally not surfaced during the initial onboarding
/// flow — ``OnboardingView`` owns that case and shows its own dedicated rows.
///
/// Each row auto-dismisses the moment ``AppConfigurationModel`` reports the
/// corresponding permission as granted again, driven by Observation.
struct PermissionRegressionBanner: View {
  private let configuration = AppConfigurationModel.shared
  @AppStorage(AppDefaultsKey.hasCompletedOnboarding) private var hasCompletedOnboarding = false

  private let microphonePermissionService = MicrophonePermissionService()
  private let accessibilityPermissionService = AccessibilityPermissionService()

  var body: some View {
    if hasCompletedOnboarding {
      VStack(spacing: 8) {
        if !configuration.microphoneGranted {
          PermissionRegressionRow(
            icon: "microphone.slash",
            title: "Microphone access is off",
            message: "L'Alfred can't record without microphone access.",
            actionTitle: "Grant microphone",
            action: requestMicrophone
          )
        }

        if !configuration.accessibilityGranted {
          PermissionRegressionRow(
            icon: "accessibility",
            title: "Accessibility access is off",
            message: "L'Alfred needs accessibility access to paste transcriptions into other apps.",
            actionTitle: "Grant accessibility",
            action: requestAccessibility
          )
        }
      }
      .padding(.horizontal)
      .padding(.top, configuration.isFullyConfigured ? 0 : 12)
      .animation(.easeInOut(duration: 0.2), value: configuration.microphoneGranted)
      .animation(.easeInOut(duration: 0.2), value: configuration.accessibilityGranted)
    }
  }

  private func requestMicrophone() {
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

  private func requestAccessibility() {
    // Returns the *current* trust value; the actual grant happens later in
    // System Settings and is picked up via the active-state observer on
    // ``AppConfigurationModel``.
    _ = accessibilityPermissionService.requestPrompt()
    configuration.refresh()
  }
}


private struct PermissionRegressionRow: View {
  let icon: String
  let title: String
  let message: String
  let actionTitle: String
  let action: () -> Void

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      Image(systemName: icon)
        .font(.title3)
        .foregroundStyle(Color.red)
        .frame(width: 24)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.headline)
        Text(message)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 12)

      Button(actionTitle, action: action)
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
    }
    .padding(12)
    .background(
      Color.red.opacity(0.08),
      in: RoundedRectangle(cornerRadius: 10, style: .continuous)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .strokeBorder(Color.red.opacity(0.35), lineWidth: 1)
    )
  }
}


#if DEBUG

#Preview("Both Missing") {
  PermissionRegressionRowsPreview(microphone: false, accessibility: false)
}

#Preview("Microphone Only") {
  PermissionRegressionRowsPreview(microphone: false, accessibility: true)
}

#Preview("Accessibility Only") {
  PermissionRegressionRowsPreview(microphone: true, accessibility: false)
}

private struct PermissionRegressionRowsPreview: View {
  let microphone: Bool
  let accessibility: Bool

  var body: some View {
    VStack(spacing: 8) {
      if !microphone {
        PermissionRegressionRow(
          icon: "microphone.slash",
          title: "Microphone access is off",
          message: "L'Alfred can't record without microphone access.",
          actionTitle: "Grant microphone",
          action: {}
        )
      }
      if !accessibility {
        PermissionRegressionRow(
          icon: "accessibility",
          title: "Accessibility access is off",
          message: "L'Alfred needs accessibility access to paste transcriptions into other apps.",
          actionTitle: "Grant accessibility",
          action: {}
        )
      }
    }
    .padding()
    .frame(width: 600)
  }
}

#endif
