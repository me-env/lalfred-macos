import SwiftUI

/// Settings section reserved for developers (whitelisted via
/// `DeveloperEmails`). Lets a developer flip the API environment between
/// production and staging, signing the user out so the next sign-in flows
/// through the newly selected backend.
///
/// The view renders nothing for non-developer users, so callers can drop it
/// in unconditionally.
struct DeveloperSection: View {
  @AppStorage(AppDefaultsKey.accountEmail) private var accountEmail = ""
  @AppStorage(AppDefaultsKey.apiEnvironment) private var apiEnvironmentRaw = APIEnvironment.production.rawValue

  private var isDeveloper: Bool {
    developerEmails.contains(accountEmail)
  }

  private var currentEnvironment: APIEnvironment {
    APIEnvironment(rawValue: apiEnvironmentRaw) ?? .production
  }

  var body: some View {
    if isDeveloper {
      SectionBoxWithTitle(
        "Developer",
        caption: "Switching environments will sign you out."
      ) {
        VStack(alignment: .leading, spacing: 10) {
          environmentPicker
          environmentURLList
        }
      }
    }
  }

  private var environmentPicker: some View {
    Picker(
      "API environment",
      selection: Binding(
        get: { currentEnvironment },
        set: { newValue in
          guard newValue != currentEnvironment else { return }
          apiEnvironmentRaw = newValue.rawValue
          AuthManager.shared.signOut()
        }
      )
    ) {
      ForEach(APIEnvironment.allCases) { env in
        Text(env.displayName).tag(env)
      }
    }
    .pickerStyle(.segmented)
  }

  private var environmentURLList: some View {
    VStack(alignment: .leading, spacing: 2) {
      ForEach(APIEnvironment.allCases) { env in
        HStack(spacing: 6) {
          Text("\(env.displayName):")
            .font(.caption)
            .foregroundStyle(.secondary)
          Text(env.baseURL.absoluteString)
            .font(.caption.monospaced())
            .foregroundStyle(env == currentEnvironment ? .primary : .secondary)
            .textSelection(.enabled)
        }
      }
    }
  }
}

// MARK: - Previews

private struct DeveloperSectionPreviewContainer: View {
  let accountEmail: String
  let environment: APIEnvironment
  private let previewDefaults: UserDefaults

  init(accountEmail: String, environment: APIEnvironment = .production) {
    self.accountEmail = accountEmail
    self.environment = environment

    let suiteName = "preview.developerSection.\(accountEmail).\(environment.rawValue)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    defaults.set(accountEmail, forKey: AppDefaultsKey.accountEmail)
    defaults.set(environment.rawValue, forKey: AppDefaultsKey.apiEnvironment)
    self.previewDefaults = defaults
  }

  var body: some View {
    DeveloperSection()
      .defaultAppStorage(previewDefaults)
      .padding()
      .frame(width: 420)
  }
}

#Preview("Developer: Production") {
  DeveloperSectionPreviewContainer(
    accountEmail: "cyprien.r25@gmail.com",
    environment: .production
  )
}

#Preview("Developer: Staging") {
  DeveloperSectionPreviewContainer(
    accountEmail: "cyprien.r25@gmail.com",
    environment: .staging
  )
}

#Preview("Non-developer (renders nothing)") {
  DeveloperSectionPreviewContainer(accountEmail: "someone@example.com")
}
