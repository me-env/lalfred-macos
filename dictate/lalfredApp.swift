import SwiftUI
import OSLog
import AppKit
import Sparkle
import Combine


private let logger = Logger(subsystem: "fr.lalfred.dictate", category: "lalfredApp")


final class AppDelegate: NSObject, NSApplicationDelegate {
  /// Keep the menu-bar runtime alive when the user closes the main window.
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    logger.info("applicationShouldHandleReopen hasVisibleWindows=\(flag)")
    showMainWindow()
    return false
  }

  /// Brings the main window to the front, instantiating it via the
  /// `lalfred://main` external-event bootstrap when it has not yet been
  /// materialized (e.g. first reopen after a suppressed launch).
  @MainActor
  func showMainWindow() {
    NSApp.activate(ignoringOtherApps: true)

    if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
      if window.isMiniaturized { window.deminiaturize(nil) }
      window.makeKeyAndOrderFront(nil)
      return
    }

    if let url = URL(string: "lalfred://main") {
      NSWorkspace.shared.open(url)
    }
  }

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
    case "main":
      // Handled by the Window scene via `.handlesExternalEvents(matching:)`.
      break
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
    logger.info("redeem key stored, opening main window")

    showMainWindow()
  }
}


@main
struct lalfredApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @State private var runtimeCoordinator = AppRuntimeCoordinator()
  @AppStorage(AppDefaultsKey.showMenuBarExtra) private var showMenuBarExtra = true
  private let updaterController: SPUStandardUpdaterController

  init() {
    updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    LaunchAtLoginService().synchronizeStoredPreference()
    runtimeCoordinator.start()
  }

  var body: some Scene {
    Window("Settings", id: "main") {
      ContentView()
    }
    .defaultLaunchBehavior(.suppressed) // no window on first launch
    .handlesExternalEvents(matching: ["main"])
    .commands {
      CommandGroup(after: .appInfo) {
        CheckForUpdatesView(updater: updaterController.updater)
      }
    }

    MenuBarExtra("L'Alfred", image: "MenuBarIcon", isInserted: $showMenuBarExtra) {
      StatusMenu()
    }
  }
}
