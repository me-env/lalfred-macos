import SwiftUI
import OSLog
import AppKit
import AVFoundation
import Sparkle
import Combine


private let logger = Logger(subsystem: "fr.lalfred.dictate", category: "lalfredApp")


final class AppDelegate: NSObject, NSApplicationDelegate {
  /// Keep the menu-bar runtime alive when the user closes the main window.
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  /// The app's steady state (`LSUIElement = YES` in Info.plist) is `.accessory`:
  /// no Dock tile, lives in the menu bar. During the onboarding phase we
  /// temporarily elevate to `.regular` so the Settings window behaves like a
  /// normal app — it owns activation, comes back to the front after System
  /// Settings round-trips for accessibility permission, and survives the
  /// trust-toggle restart that macOS would otherwise hide.
  ///
  /// Done in `applicationWillFinishLaunching` (before any windows materialize)
  /// to avoid a Dock-tile flash on launch.
  func applicationWillFinishLaunching(_ notification: Notification) {
    UserDefaults.standard.register(defaults: [AppDefaultsKey.smartPasteFormatting: true])

    Task { @MainActor in
      applyActivationPolicy()
      observeActivationPolicyTriggers()
      observeConfigurationChanges()
    }
  }

  /// The scene declares `.defaultLaunchBehavior(.suppressed)` so users who
  /// already finished onboarding and have all permissions land directly in
  /// the menu bar. When the user still needs the Settings window (onboarding
  /// in progress or a post-onboarding permission regression) we surface it.
  func applicationDidFinishLaunching(_ notification: Notification) {
    Task { @MainActor in
      guard shouldTheAppBeForeground else {
        logger.info("launch: foreground not needed, staying in menu bar")
        return
      }
      logger.info("launch: surfacing settings window")
      showMainWindow()
    }
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
    logger.info("application \(urls)")
    guard !urls.isEmpty else {
      logger.error("Application open URL event received with no URLs")
      return
    }

    for url in urls {
      route(url: url)
    }
  }

  /// Routes incoming `lalfred://…` URLs. Auth callbacks are handled by
  /// ``AuthManager``.
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
    case "main":
      // Handled by the Window scene via `.handlesExternalEvents(matching:)`.
      break
    default:
      logger.error("unknown lalfred host: \(host, privacy: .public)")
    }
  }

  // MARK: - Activation policy

  /// True whenever the user needs the Settings window in front of them:
  ///
  /// * Onboarding is in progress — they're being walked through setup.
  /// * Post-onboarding, any prerequisite has regressed (signed out, mic
  ///   or accessibility revoked). For permissions, we additionally need a
  ///   real Dock tile so System Settings round-trips return focus to the
  ///   app and the accessibility-trust toggle doesn't silently kill us.
  @MainActor
  private var shouldTheAppBeForeground: Bool {
    if !UserDefaults.standard.bool(forKey: AppDefaultsKey.hasCompletedOnboarding) {
      return true
    }
    return !AppConfigurationModel.shared.isFullyConfigured
  }

  @MainActor
  private func applyActivationPolicy() {
    let desired: NSApplication.ActivationPolicy = shouldTheAppBeForeground ? .regular : .accessory
    guard NSApp.activationPolicy() != desired else { return }
    logger.info("activation policy → \(desired == .regular ? "regular" : "accessory", privacy: .public)")
    NSApp.setActivationPolicy(desired)

    // The .regular → .accessory transition strips the Dock tile and, as a
    // side-effect, deactivates the app — sending whatever window is on
    // screen behind other apps. Re-front the main window so the user keeps
    // looking at what they were just interacting with (e.g. the onboarding
    // completion modal after they hit "Continue").
    if desired == .accessory,
       let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }),
       window.isVisible {
      NSApp.activate(ignoringOtherApps: true)
      window.makeKeyAndOrderFront(nil)
    }
  }

  /// Re-evaluates the activation policy whenever the inputs to
  /// ``shouldTheAppBeForeground`` can change: `hasCompletedOnboarding` via
  /// `UserDefaults` (it's `@AppStorage`-backed), and the live permission
  /// state via `AppConfigurationModel`.
  @MainActor
  private func observeActivationPolicyTriggers() {
    NotificationCenter.default.addObserver(
      forName: UserDefaults.didChangeNotification,
      object: UserDefaults.standard,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.applyActivationPolicy()
      }
    }
  }

  /// `withObservationTracking` fires exactly once per registration, so we
  /// re-arm it after every change to keep tracking subsequent mutations.
  @MainActor
  private func observeConfigurationChanges() {
    withObservationTracking {
      _ = AppConfigurationModel.shared.isFullyConfigured
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        self?.applyActivationPolicy()
        self?.observeConfigurationChanges()
      }
    }
  }
}


@main
struct lalfredApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @State private var shortcuts: Shortcuts
  @State private var runtimeCoordinator: AppRuntimeCoordinator
  @AppStorage(AppDefaultsKey.showMenuBarExtra) private var showMenuBarExtra = true
  private let updaterController: SPUStandardUpdaterController

  init() {
    let shortcuts = Shortcuts()
    let coordinator = AppRuntimeCoordinator(shortcuts: shortcuts)
    
//   #if DEBUG
//   UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
//   #endif
    
    _shortcuts = State(initialValue: shortcuts)
    _runtimeCoordinator = State(initialValue: coordinator)
    updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    LaunchAtLoginService().synchronizeStoredPreference()
    coordinator.start()
  }

  var body: some Scene {
    Window("Settings", id: "main") {
      ContentView()
        .environment(shortcuts)
        .environment(\.sparkleUpdater, updaterController.updater)
    }
    // Suppressed by default; AppDelegate.applicationDidFinishLaunching opens
    // the window when the user is not yet signed in or is missing permissions.
    .defaultLaunchBehavior(.suppressed)
    .handlesExternalEvents(matching: ["main"])

    MenuBarExtra("L'Alfred", image: "MenuBarIcon", isInserted: $showMenuBarExtra) {
      StatusMenu()
        .environment(\.sparkleUpdater, updaterController.updater)
    }
  }
}
