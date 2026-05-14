import SwiftUI
import AppKit

struct StatusMenu: View {
  @Environment(\.openSettings) private var openSettings
  @Environment(\.openWindow) private var openWindow
  @Environment(\.sparkleUpdater) private var sparkleUpdater

  var body: some View {
    Group {
      settingsButton
      Divider()
      if let sparkleUpdater {
        CheckForUpdatesView(updater: sparkleUpdater)
      }
      quitButton
      
      versionLabel
    }
  }
  
  private var settingsButton: some View {
    Button {
      openAppSettings()
    } label: {
      Label("Settings", systemImage: "gearshape")
    }
    .keyboardShortcut(",")
  }

  @MainActor
  private func openAppSettings() {
    NSApp.activate(ignoringOtherApps: true)
    openWindow(id: "main")
  }

  private var quitButton: some View {
    Button {
      NSApplication.shared.terminate(nil)
    } label: {
      Label("Quit", systemImage: "xmark.circle")
    }
    .keyboardShortcut("q")
  }
  
  private var versionLabel: some View {
    Text("\(AppVersion.name) \(AppVersion.version)")
      .foregroundStyle(.secondary)
  }
}

#Preview {
  StatusMenu()
}
