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
            modifiers: [.command, .shift]
          ),
          activeShortcutEditorID: $activeShortcutEditorID
        )
        Divider()
        ShortcutInput(
          label: "Hold to Speak",
          storeKey: AppDefaultsKey.shortcutHoldToSpeak,
          fallbackShortcut: Shortcut(
            keyCode: Shortcut.modifierOnlyKeyCode,
            modifiers: [.option, .control]
          ),
          allowModifierOnlyShortcut: true,
          activeShortcutEditorID: $activeShortcutEditorID
        )
        Divider()
        ShortcutInput(
          label: "Mode Switcher",
          storeKey: AppDefaultsKey.shortcutModeSwitcher,
          fallbackShortcut: Shortcut(
            keyCode: KeyCode.from(character: "/") ?? 44,
            modifiers: [.command]
          ),
          activeShortcutEditorID: $activeShortcutEditorID
        )
      }
      PermissionsInput()
      APIKeyInputView()
    }
    .padding()
    .textFieldStyle(.roundedBorder)
  }
}


enum Tabs {
  case home
  case modes
  case dictionary
  case snippets
  case account
}

struct TabsView: View {
  @State private var currentTab: Tabs
  @State private var measuredTabHeights: [Tabs: CGFloat] = [:]
  @State private var settingsWindow: NSWindow?
  
  private let minimumSettingsWidth: CGFloat = 640
  private let minimumSettingsHeight: CGFloat = 320
  private let tabBarChromeHeight: CGFloat = 80
  
  init(initialTab: Tabs = .home) {
    _currentTab = State(initialValue: initialTab)
  }
  
  var body: some View {
    TabView(selection: $currentTab) {
      Group {
        GeneralTabView()
          .tabItem {
            Text("General")
            Image(systemName: currentTab == .home ? "gearshape.fill" : "gearshape")
          }
          .tag(Tabs.home)
        
        ModesTabView()
          .tabItem {
            Text("Modes")
            Image(systemName: currentTab == .modes ? "slider.horizontal.3" : "slider.horizontal.3")
          }
          .tag(Tabs.modes)
        
        DictionaryTabView()
          .tabItem {
            Text("Dictionary")
            Image(systemName: currentTab == .dictionary ? "book.fill" : "book")
          }
          .tag(Tabs.dictionary)
        
        SnippetsTabView()
          .tabItem {
            Text("Snippets")
            Image(systemName: currentTab == .snippets ? "text.bubble.fill" : "text.bubble")
          }
          .tag(Tabs.snippets)
        
        AccountTabView()
          .tabItem {
            Text("Account")
            Image(systemName: currentTab == .account ? "person.crop.circle.fill" : "person.crop.circle")
          }
          .tag(Tabs.account)
      }.frame(width: 800)
    }
    .tabViewStyle(.tabBarOnly)
    .navigationTitle("L'Alfred")
  }
}
  
  
struct ContentView: View {
  private let initialTab: Tabs

  init(initialTab: Tabs = .home) {
    self.initialTab = initialTab
  }

  var body: some View {
    TabsView(initialTab: initialTab)
  }
}

#Preview("General") {
  ContentView(initialTab: .home)
}

#Preview("Modes") {
  ContentView(initialTab: .modes)
}

#Preview("Dictionary") {
  ContentView(initialTab: .dictionary)
}

#Preview("Snippets") {
  ContentView(initialTab: .snippets)
}

#Preview("Account") {
  ContentView(initialTab: .account)
}


