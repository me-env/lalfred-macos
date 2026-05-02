//
//  ContentView.swift
//  dictate
//
//  Created by Cyprien Ricque on 4/26/26.
//

import SwiftUI
import AppKit


struct GeneralTabView: View {
  @State private var activeShortcutEditorID: String?

  var body: some View {
    VStack {
      PreferencesInput()
      SectionBox("Keyboard Shortcuts") {
        ShortcutInput(
          label: "Toggle Recording",
          storeKey: AppDefaultsKey.shortcutToggleRecording,
          fallbackShortcut: Shortcut(
            keyCode: KeyCode.from(character: " ") ?? 49,
            modifiers: [.control, .option]
          ),
          activeShortcutEditorID: $activeShortcutEditorID
        )
        Divider()
        ShortcutInput(
          label: "Hold to Speak",
          storeKey: AppDefaultsKey.shortcutHoldToSpeak,
          fallbackShortcut: Shortcut(
            keyCode: KeyCode.from(character: " ") ?? 49,
            modifiers: [.control, .shift]
          ),
          activeShortcutEditorID: $activeShortcutEditorID
        )
        Divider()
        ShortcutInput(
          label: "Mode Switcher",
          storeKey: AppDefaultsKey.shortcutModeSwitcher,
          fallbackShortcut: Shortcut(
            keyCode: KeyCode.from(character: "m") ?? 46,
            modifiers: [.control, .shift]
          ),
          activeShortcutEditorID: $activeShortcutEditorID
        )
      }
      PermissionsInput()
      APIKeyInputView()
    }
    .frame(maxWidth: 600)
    .padding()
    .textFieldStyle(.roundedBorder)
    .onAppear {
      DispatchQueue.main.async {
        NSApp.keyWindow?.makeFirstResponder(nil)
      }
    }
  }
}

enum Tabs {
  case home
  case dictionary
  case snippets
  case account
}

struct TabsView: View {
  @State var currentTab: Tabs = .home
  @State private var measuredTabHeights: [Tabs: CGFloat] = [:]
  @State private var settingsWindow: NSWindow?

  private let minimumSettingsWidth: CGFloat = 640
  private let minimumSettingsHeight: CGFloat = 320
  private let tabBarChromeHeight: CGFloat = 80
  
  var body: some View {
    TabView(selection: $currentTab) {
      GeneralTabView()
        .recordTabHeight(.home)
        .tabItem {
          Text("General")
          Image(systemName: currentTab == .home ? "gearshape.fill" : "gearshape")
        }
        .tag(Tabs.home)
      
      DictionaryTabView()
        .recordTabHeight(.dictionary)
        .tabItem {
          Text("Dictionary")
          Image(systemName: currentTab == .dictionary ? "book.fill" : "book")
        }
        .tag(Tabs.dictionary)

      SnippetsTabView()
        .recordTabHeight(.snippets)
        .tabItem {
          Text("Snippets")
          Image(systemName: currentTab == .snippets ? "text.bubble.fill" : "text.bubble")
        }
        .tag(Tabs.snippets)

      AccountTabView()
        .recordTabHeight(.account)
        .tabItem {
          Text("Account")
          Image(systemName: currentTab == .account ? "person.crop.circle.fill" : "person.crop.circle")
        }
        .tag(Tabs.account)
    }
    .tabViewStyle(.tabBarOnly)
    .navigationTitle("Dictate")
    .frame(minWidth: minimumSettingsWidth, minHeight: minimumSettingsHeight)
    .background(
      SettingsWindowReader { window in
        if settingsWindow !== window {
          settingsWindow = window
          resizeSettingsWindow(animated: false)
        }
      }
    )
    .onPreferenceChange(TabHeightPreferenceKey.self) { heights in
      measuredTabHeights.merge(heights) { _, new in new }
      resizeSettingsWindow(animated: false)
    }
    .onChange(of: currentTab) { _, _ in
      resizeSettingsWindow(animated: true)
    }
    .onAppear {
      resizeSettingsWindow(animated: false)
    }
  }

  private func resizeSettingsWindow(animated: Bool) {
    guard let window = settingsWindow else { return }

    window.minSize = NSSize(width: minimumSettingsWidth, height: minimumSettingsHeight)

    guard let tabContentHeight = measuredTabHeights[currentTab], tabContentHeight > 0 else { return }

    let targetHeight = max(
      minimumSettingsHeight,
      ceil(tabContentHeight + tabBarChromeHeight)
    )

    var frame = window.frame
    let targetWidth = max(frame.width, minimumSettingsWidth)

    guard abs(frame.height - targetHeight) > 1 || abs(frame.width - targetWidth) > 1 else {
      return
    }

    let deltaHeight = targetHeight - frame.height
    frame.size.width = targetWidth
    frame.size.height = targetHeight
    frame.origin.y -= deltaHeight

    window.setFrame(frame, display: true, animate: animated)
  }
}

private struct SettingsWindowReader: NSViewRepresentable {
  let onResolve: (NSWindow?) -> Void

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    DispatchQueue.main.async {
      onResolve(view.window)
    }
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    DispatchQueue.main.async {
      onResolve(nsView.window)
    }
  }
}

private struct TabHeightPreferenceKey: PreferenceKey {
  static var defaultValue: [Tabs: CGFloat] = [:]

  static func reduce(value: inout [Tabs: CGFloat], nextValue: () -> [Tabs: CGFloat]) {
    value.merge(nextValue()) { _, new in new }
  }
}

private struct TabHeightRecorder: ViewModifier {
  let tab: Tabs

  func body(content: Content) -> some View {
    content.background(
      GeometryReader { proxy in
        Color.clear.preference(
          key: TabHeightPreferenceKey.self,
          value: [tab: proxy.size.height]
        )
      }
    )
  }
}

private extension View {
  func recordTabHeight(_ tab: Tabs) -> some View {
    modifier(TabHeightRecorder(tab: tab))
  }
}

struct ContentView: View {
  var body: some View {
    TabsView()
  }
}

#Preview {
  ContentView()
}
