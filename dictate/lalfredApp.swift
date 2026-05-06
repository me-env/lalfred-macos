import SwiftUI
import OSLog
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
  private let logger = Logger(subsystem: "fr.lalfred.dictate", category: "URL")

  func application(_ application: NSApplication, open urls: [URL]) {
    guard !urls.isEmpty else {
      logger.error("Application open URL event received with no URLs")
      return
    }

    for url in urls {
      route(url: url)
    }
  }

  /// Routes incoming `lalfred://…` URLs. Auth callbacks are handled by
  /// ``AuthManager``; redemption deep links populate
  /// ``RedeemDeepLinkCoordinator`` and surface the Settings window.
  @MainActor
  private func route(url: URL) {
    logger.info("incoming url=\(url.absoluteString, privacy: .public)")

    guard url.scheme?.lowercased() == "lalfred" else {
      logger.error("ignoring non-lalfred scheme")
      return
    }

    let host = url.host?.lowercased() ?? ""
    switch host {
    case "auth":
      let handled = AuthManager.shared.handleIncomingURL(url)
      logger.info("auth callback handled=\(handled, privacy: .public)")
    case "redeem":
      handleRedeemURL(url)
    default:
      logger.error("unknown lalfred host: \(host, privacy: .public)")
    }
  }

  @MainActor
  private func handleRedeemURL(_ url: URL) {
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    guard let key = components?.queryItems?.first(where: { $0.name == "key" })?.value,
          !key.isEmpty
    else {
      logger.error("redeem URL missing 'key' query item")
      return
    }

    RedeemDeepLinkCoordinator.shared.setPending(key)
    logger.info("redeem key stored, opening Settings")

    NSApp.activate(ignoringOtherApps: true)
    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
  }
}

@main
struct lalfredApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @State private var runtimeCoordinator = AppRuntimeCoordinator()
  @AppStorage(AppDefaultsKey.showMenuBarExtra) private var showMenuBarExtra = true

  init() {
    LaunchAtLoginService().synchronizeStoredPreference()
    runtimeCoordinator.start()
  }

  var body: some Scene {
    Settings {
      ContentView()
    }

    MenuBarExtra("L'Alfred", image: "MenuBarIcon", isInserted: $showMenuBarExtra) {
      StatusMenu()
    }
  }
}
