import SwiftUI
import AppKit

struct StatusMenu: View {
  @Environment(\.openSettings) private var openSettings
  @State private var localKeyMonitor: Any?
  
  var body: some View {
    Group {
      settingsButton
      Divider()
      versionLabel
      quitButton
    }
    .onAppear {
      installLocalSettingsShortcutMonitorIfNeeded()
    }
    .onDisappear {
      removeLocalSettingsShortcutMonitor()
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
    openSettings()
    NSApp.activate()
  }

  private func installLocalSettingsShortcutMonitorIfNeeded() {
    guard localKeyMonitor == nil else { return }

    localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      if isOpenSettingsShortcutEvent(event) {
        openAppSettings()
        return nil
      }
      return event
    }
  }

  private func removeLocalSettingsShortcutMonitor() {
    guard let localKeyMonitor else { return }
    NSEvent.removeMonitor(localKeyMonitor)
    self.localKeyMonitor = nil
  }

  private func isOpenSettingsShortcutEvent(_ event: NSEvent) -> Bool {
    let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    return modifiers == [.command] && event.charactersIgnoringModifiers == ","
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
