import SwiftUI

struct ConnectedAccountCard: View {
  let model: AccountTabViewModel

  @AppStorage(AppDefaultsKey.accountEmail) private var accountEmail = ""
  @AppStorage(AppDefaultsKey.accountFirstName) private var accountFirstName = ""
  @AppStorage(AppDefaultsKey.accountLastName) private var accountLastName = ""
  @AppStorage(AppDefaultsKey.accountCredits) private var accountCredits = -1
  @AppStorage(AppDefaultsKey.accountIsSubscribed) private var accountIsSubscribed = false

  var body: some View {
    VStack(alignment: .leading) {
      if model.accountDetailsErrorMessage.isEmpty {
        detailsContent
      } else {
        errorContent
      }
    }
    .accountCardBackground()
  }

  // MARK: - Details

  @ViewBuilder
  private var detailsContent: some View {
    if isLoadingName {
      HStack(spacing: 8) {
        ProgressView()
          .controlSize(.small)
        Text("Loading account details...")
          .font(.title3.weight(.semibold))
          .foregroundStyle(.secondary)
      }
    } else {
      Text(displayName)
        .font(.title3.weight(.semibold))
    }

    if isLoadingEmail {
      Text("Loading email...")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .redacted(reason: .placeholder)
    } else {
      Text(accountEmail)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
    }

    subscriptionBadge
      .padding(.top, 4)

    Divider()
      .padding(.vertical, 4)

    HStack(alignment: .center) {
      if isLoadingCredits {
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text("Loading credits...")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
        }
      } else {
        Text(creditsLabel)
          .font(.subheadline.weight(.medium))
          .foregroundStyle(.primary)
      }

      Spacer()

      Button("Sign out", role: .destructive) {
        model.signOut()
      }
      .buttonStyle(.borderless)
    }
  }

  // MARK: - Error

  private var errorContent: some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 10) {
        Text("Couldn't load account details")
          .font(.title3.weight(.semibold))

        Text(model.accountDetailsErrorMessage)
          .font(.subheadline)
          .foregroundStyle(.red)

        Button(model.isLoadingAccountDetails ? "Retrying..." : "Try again") {
          Task {
            await model.loadAccountDetails()
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.isLoadingAccountDetails)
      }

      Spacer()

      Button("Sign out", role: .destructive) {
        model.signOut()
      }
      .buttonStyle(.borderless)
    }
  }

  // MARK: - Subscription badge

  private var subscriptionBadge: some View {
    HStack(spacing: 4) {
      Image(systemName: accountIsSubscribed ? "checkmark.seal.fill" : "xmark.seal.fill")
        .foregroundStyle(accountIsSubscribed ? .green : .secondary)
        .font(.caption)
      Text(accountIsSubscribed ? "Subscribed" : "No active subscription")
        .font(.caption.weight(.medium))
        .foregroundStyle(accountIsSubscribed ? .green : .secondary)
    }
  }

  // MARK: - Derived display state

  private var displayName: String {
    let first = accountFirstName.trimmingCharacters(in: .whitespacesAndNewlines)
    let last = accountLastName.trimmingCharacters(in: .whitespacesAndNewlines)
    let fullName = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
    return fullName.isEmpty ? "Account" : fullName
  }

  private var trimmedEmail: String {
    accountEmail.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var isLoadingName: Bool {
    model.isLoadingAccountDetails && displayName == "Account"
  }

  private var isLoadingEmail: Bool {
    model.isLoadingAccountDetails && trimmedEmail.isEmpty
  }

  private var isLoadingCredits: Bool {
    model.isLoadingAccountDetails && accountCredits < 0
  }

  private var creditsLabel: String {
    guard accountCredits >= 0 else {
      return "Credits unavailable"
    }
    let formatted = accountCredits.formatted(.number.grouping(.automatic))
    return "\(formatted) credits"
  }
}
