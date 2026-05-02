import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ModesTabView: View {
  @State private var activeShortcutEditorID: String?
  private let fixedTabHeight: CGFloat = 430
  
  var body: some View {
    VStack(spacing: 12) {
      SectionBox(
        "Modes",
        caption: "Modes are fixed for now. You can configure one app and one trigger shortcut for each mode."
      ) {
        ForEach(Array(ModeCatalog.definitions.enumerated()), id: \.element.id) { index, mode in
          ModeConfigurationCard(
            mode: mode,
            activeShortcutEditorID: $activeShortcutEditorID
          )
          
          if index < ModeCatalog.definitions.count - 1 {
            Divider()
          }
        }
      }
    }
    .padding()
    .textFieldStyle(.roundedBorder)
  }
}

private struct ModeConfigurationCard: View {
  let mode: ModeCatalog.ModeDefinition
  @Binding var activeShortcutEditorID: String?
  
  @State private var selectedApplicationPath: String?
  
  private var appStore: ModeApplicationDefaultsStore {
    ModeApplicationDefaultsStore(key: mode.applicationStoreKey)
  }
  
  private var selectedApplicationURL: URL? {
    guard let selectedApplicationPath else { return nil }
    return URL(fileURLWithPath: selectedApplicationPath)
  }
  
  init(mode: ModeCatalog.ModeDefinition, activeShortcutEditorID: Binding<String?>) {
    self.mode = mode
    _activeShortcutEditorID = activeShortcutEditorID
    _selectedApplicationPath = State(initialValue: ModeApplicationDefaultsStore(key: mode.applicationStoreKey).loadPath())
  }
  
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        Image(systemName: mode.icon)
          .foregroundStyle(mode.iconColor)
          .font(.system(size: 14, weight: .medium))
        Text(mode.title)
          .font(.headline)
      }

      Text(mode.detail)
        .font(.subheadline)
        .foregroundStyle(.secondary)
      
      HStack(alignment: .center, spacing: 8) {
        Text(selectedApplicationName)
          .font(.callout)
          .lineLimit(1)
          .truncationMode(.middle)
        
        Spacer()
        
        Button("Choose App") {
          selectApplication()
        }
        
        Button("Clear", role: .destructive) {
          clearApplication()
        }
        .disabled(selectedApplicationPath == nil)
      }
      
      ShortcutInput(
        label: "Trigger Shortcut",
        storeKey: mode.shortcutStoreKey,
        fallbackShortcut: mode.fallbackShortcut,
        activeShortcutEditorID: $activeShortcutEditorID
      )
    }
  }
  
  private var selectedApplicationName: String {
    guard let selectedApplicationURL else { return "No application selected" }
    guard let bundle = Bundle(url: selectedApplicationURL) else {
      return selectedApplicationURL.deletingPathExtension().lastPathComponent
    }
    
    let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
    let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
    return displayName ?? name ?? selectedApplicationURL.deletingPathExtension().lastPathComponent
  }
  
  private func selectApplication() {
    let panel = NSOpenPanel()
    panel.title = "Choose application for \(mode.title) mode"
    panel.prompt = "Choose"
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [.application]
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    
    guard panel.runModal() == .OK, let appURL = panel.url else { return }
    selectedApplicationPath = appURL.path
    appStore.savePath(appURL.path)
  }
  
  private func clearApplication() {
    selectedApplicationPath = nil
    appStore.removePath()
  }
}

private struct ModeApplicationDefaultsStore {
  let key: String
  private let userDefaults: UserDefaults
  
  init(key: String, userDefaults: UserDefaults = .standard) {
    self.key = key
    self.userDefaults = userDefaults
  }
  
  func loadPath() -> String? {
    userDefaults.string(forKey: key)
  }
  
  func savePath(_ path: String) {
    userDefaults.set(path, forKey: key)
  }
  
  func removePath() {
    userDefaults.removeObject(forKey: key)
  }
}

#Preview {
  ModesTabView()
}
