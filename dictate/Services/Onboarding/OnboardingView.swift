import SwiftUI
import AppKit
import AVFoundation
import os


private let logger = Logger(subsystem: "fr.lalfred.dictate", category: "OnboardingView")


/// Forced first-run onboarding flow.
///
/// Replaces the entire `ContentView` root while
/// ``AppConfigurationModel/isFullyConfigured`` is `false`. Because there's no
/// surrounding chrome the user can interact with, the only way out is to
/// complete all three steps — no dismiss button, no escape hatch.
///
/// Step completion is derived directly from the corresponding observable
/// boolean on ``AppConfigurationModel``, so the active row auto-advances as
/// soon as the underlying state flips (OAuth callback returns, microphone
/// prompt is accepted, accessibility trust toggled in System Settings…).
struct OnboardingView: View {
  private let configuration = AppConfigurationModel.shared
  private let microphonePermissionService = MicrophonePermissionService()
  private let accessibilityPermissionService = AccessibilityPermissionService()

  @State private var accountModel = AccountTabViewModel()

  private let steps: [OnboardingStep] = [.signIn, .microphone, .accessibility]

  private var currentStep: OnboardingStep {
    steps.first { !$0.isComplete(configuration) } ?? .accessibility
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 28) {
        header

        VStack(spacing: 10) {
          ForEach(steps, id: \.self) { step in
            OnboardingStepRow(
              step: step,
              state: state(for: step),
              isLoading: isLoading(for: step),
              errorMessage: errorMessage(for: step),
              action: { perform(step) }
            )
          }
        }

        footer
      }
      .frame(maxWidth: 520)
      .padding(.horizontal, 40)
      .padding(.vertical, 32)
      .frame(maxWidth: .infinity)
    }
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private var header: some View {
    VStack(spacing: 10) {
      Image(nsImage: NSApp.applicationIconImage)
        .resizable()
        .frame(width: 64, height: 64)

      Text("Welcome to L'Alfred")
        .font(.title.weight(.semibold))

      Text("Three quick steps and you'll be dictating.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .multilineTextAlignment(.center)
  }

  private var footer: some View {
    Text("Once you're set up, L'Alfred lives in your menu bar.")
      .font(.caption)
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)
  }

  private func state(for step: OnboardingStep) -> OnboardingStepRow.State {
    if step.isComplete(configuration) {
      return .complete
    }
    return step == currentStep ? .active : .pending
  }

  private func isLoading(for step: OnboardingStep) -> Bool {
    step == .signIn && accountModel.isLoadingAuthURL
  }

  private func errorMessage(for step: OnboardingStep) -> String? {
    guard step == .signIn else { return nil }
    let message = accountModel.authErrorMessage
    return message.isEmpty ? nil : message
  }

  private func perform(_ step: OnboardingStep) {
    switch step {
    case .signIn:
      Task { await accountModel.startGoogleOAuth() }
    case .microphone:
      requestMicrophone()
    case .accessibility:
      requestAccessibility()
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


enum OnboardingStep: Hashable {
  case signIn
  case microphone
  case accessibility

  var title: String {
    switch self {
    case .signIn:        return "Sign in with Google"
    case .microphone:    return "Allow microphone access"
    case .accessibility: return "Allow accessibility access"
    }
  }

  var caption: String {
    switch self {
    case .signIn:
      return "Tracks your credits and lets you bring your own API keys."
    case .microphone:
      return "Required so L'Alfred can hear what you say."
    case .accessibility:
      return "Required so L'Alfred can paste transcriptions into other apps."
    }
  }

  var actionTitle: String {
    switch self {
    case .signIn:        return "Continue with Google"
    case .microphone:    return "Grant microphone"
    case .accessibility: return "Grant accessibility"
    }
  }

  var systemImage: String {
    switch self {
    case .signIn:        return "person.crop.circle"
    case .microphone:    return "microphone"
    case .accessibility: return "accessibility"
    }
  }

  func isComplete(_ configuration: AppConfigurationModel) -> Bool {
    switch self {
    case .signIn:        return configuration.isSignedIn
    case .microphone:    return configuration.microphoneGranted
    case .accessibility: return configuration.accessibilityGranted
    }
  }
}


private struct OnboardingStepRow: View {
  enum State { case pending, active, complete }

  let step: OnboardingStep
  let state: State
  let isLoading: Bool
  let errorMessage: String?
  let action: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      statusIcon
        .frame(width: 28, height: 28)

      VStack(alignment: .leading, spacing: 4) {
        Text(step.title)
          .font(.headline)
          .foregroundStyle(state == .pending ? Color.secondary : Color.primary)

        Text(step.caption)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)

        if state == .active {
          Button(action: action) {
            HStack(spacing: 6) {
              if isLoading {
                ProgressView()
                  .controlSize(.small)
              }
              Text(isLoading ? "Opening…" : step.actionTitle)
            }
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.regular)
          .disabled(isLoading)
          .padding(.top, 6)
        }

        if let errorMessage {
          Text(errorMessage)
            .font(.caption)
            .foregroundStyle(.red)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 2)
        }
      }

      Spacer(minLength: 0)
    }
    .padding(16)
    .background(
      .quaternary.opacity(state == .active ? 0.35 : 0.15),
      in: RoundedRectangle(cornerRadius: 12, style: .continuous)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .strokeBorder(
          state == .active ? Color.accentColor.opacity(0.55) : Color.gray.opacity(0.2),
          lineWidth: state == .active ? 1.2 : 1
        )
    )
    .animation(.easeInOut(duration: 0.2), value: state)
  }

  @ViewBuilder
  private var statusIcon: some View {
    switch state {
    case .complete:
      Image(systemName: "checkmark.circle.fill")
        .font(.title2)
        .foregroundStyle(Color.green)
    case .active:
      Image(systemName: step.systemImage)
        .font(.title2)
        .foregroundStyle(.tint)
    case .pending:
      Image(systemName: step.systemImage)
        .font(.title2)
        .foregroundStyle(.tertiary)
    }
  }
}


#Preview("Onboarding: Fresh start") {
  OnboardingView()
    .frame(width: 740, height: 520)
}
