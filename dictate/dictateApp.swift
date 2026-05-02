//
//  dictateApp.swift
//  dictate
//
//  Created by Cyprien Ricque on 4/26/26.
//

import SwiftUI
import OSLog
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
  private let logger = Logger(subsystem: "fr.lalfred.app", category: "Auth")

  func application(_ application: NSApplication, open urls: [URL]) {
    guard !urls.isEmpty else {
      logger.error("Application open URL event received with no URLs")
      return
    }

    for url in urls {
      logger.info("Received OAuth callback URL: \(url.absoluteString, privacy: .public)")
      let handled = AuthManager.shared.handleIncomingURL(url)
      logger.info("OAuth callback handled: \(handled, privacy: .public)")
    }
  }
}

@main
struct dictateApp: App {
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
