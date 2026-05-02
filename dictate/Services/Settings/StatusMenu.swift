import SwiftUI
import AppKit

struct StatusMenu: View {
  @Environment(\.openSettings) private var openSettings
  
  var body: some View {
    Group {
      settingsButton
      Divider()
      versionLabel
      quitButton
    }
  }
  
  private var settingsButton: some View {
    Button {
      openAppSettings()
    } label: {
      Label("Settings...", systemImage: "gearshape")
    }
    .keyboardShortcut(",")
  }

  @MainActor
  private func openAppSettings() {
    NSApp.activate(ignoringOtherApps: true)
    openSettings()
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
    let name = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "App"
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
    return Text("\(name) \(version) (\(build))")
      .foregroundStyle(.secondary)
  }
}

#Preview {
  StatusMenu()
}
