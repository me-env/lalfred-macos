import SwiftUI
import AppKit


struct GeneralTabView: View {
  @State private var activeShortcutEditorID: String?
  
  var body: some View {
    VStack {
      PreferencesInput()
      SectionBoxWithTitle("Keyboard Shortcuts") {
        ShortcutInput(
          label: "Toggle Recording",
          storeKey: AppDefaultsKey.shortcutToggleRecording,
          defaultShortcut: AppDefaultShortcuts.toggleRecording,
          activeShortcutEditorID: $activeShortcutEditorID
        )
        Divider()
        ShortcutInput(
          label: "Hold to Speak",
          storeKey: AppDefaultsKey.shortcutHoldToSpeak,
          defaultShortcut: AppDefaultShortcuts.holdToSpeak,
          activeShortcutEditorID: $activeShortcutEditorID
        )
      }
      PermissionsInput()
    }
    .padding()
    .textFieldStyle(.roundedBorder)
  }
}


enum Tabs {
  case home
  case dictionary
  case snippets
  case sounds
  case account
}

struct TabsView: View {
  @State private var currentTab: Tabs
  @State private var measuredTabHeights: [Tabs: CGFloat] = [:]
  @State private var settingsWindow: NSWindow?

  private let deepLinkCoordinator = RedeemDeepLinkCoordinator.shared

  private let minimumSettingsWidth: CGFloat = 640
  private let minimumSettingsHeight: CGFloat = 320
  private let tabBarChromeHeight: CGFloat = 80

  init(initialTab: Tabs = .home) {
    _currentTab = State(initialValue: initialTab)
  }
  
  var body: some View {
    TabView(selection: $currentTab) {
      TabSection {
        Tab(
          "General",
          systemImage: currentTab == .home ? "gearshape.fill" : "gearshape",
          value: Tabs.home,
          role: nil
        ) {
          GeneralTabView()
        }
      }
      
      TabSection {
        Tab(
          "Dict",
          systemImage: currentTab == .dictionary ? "book.fill" : "book",
          value: Tabs.dictionary,
          role: nil
        ) {
          DictionaryTabView()
        }
        
        Tab(
          "Snippets",
          systemImage: currentTab == .snippets ? "text.bubble.fill" : "text.bubble",
          value: Tabs.snippets,
          role: nil
        ) {
          SnippetsTabView()
        }
      }
      
      TabSection {
        Tab(
          "Sounds",
          systemImage: currentTab == .sounds ? "speaker.wave.2.fill" : "speaker.wave.2",
          value: Tabs.sounds,
          role: nil
        ) {
          SoundsTabView()
        }
        
        Tab(
          "Account",
          systemImage: currentTab == .account ? "person.crop.circle.fill" : "person.crop.circle",
          value: Tabs.account,
          role: nil
        ) {
          AccountTabView()
        }
      }
    }
    .tabViewStyle(.sidebarAdaptable)
    .tabViewSidebarBottomBar {
      Text("L'Alfred")
        .padding(6)
    }
    .background(Color(red:0.12549, green:0.12549, blue:0.11765 ))
    .onAppear {
      jumpToAccountIfRedeemPending()
    }
    .onChange(of: deepLinkCoordinator.pendingKey) { _, newValue in
      if newValue != nil {
        currentTab = .account
      }
    }
  }

  private func jumpToAccountIfRedeemPending() {
    if deepLinkCoordinator.pendingKey != nil {
      currentTab = .account
    }
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

#Preview("Dictionary") {
  ContentView(initialTab: .dictionary)
}

#Preview("Snippets") {
  ContentView(initialTab: .snippets)
}

#Preview("Sounds") {
  ContentView(initialTab: .sounds)
}

#Preview("Account") {
  ContentView(initialTab: .account)
}

