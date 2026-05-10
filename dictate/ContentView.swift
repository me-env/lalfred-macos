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
    .padding([.bottom, .horizontal])
    .textFieldStyle(.roundedBorder)
  }
}


enum Tabs: Hashable, CaseIterable {
  case home
  case dictionary
  case snippets
  case sounds
  case account

  var title: String {
    switch self {
    case .home:
      "General"
    case .dictionary:
      "Dictionary"
    case .snippets:
      "Snippets"
    case .sounds:
      "Sounds"
    case .account:
      "Account"
    }
  }

  var systemImage: String {
    switch self {
    case .home:
      "gearshape"
    case .dictionary:
      "book"
    case .snippets:
      "text.bubble"
    case .sounds:
      "speaker.wave.2"
    case .account:
      "person.crop.circle"
    }
  }

  var selectedSystemImage: String {
    switch self {
    case .home:
      "gearshape.fill"
    case .dictionary:
      "book.fill"
    case .snippets:
      "text.bubble.fill"
    case .sounds:
      "speaker.wave.2.fill"
    case .account:
      "person.crop.circle.fill"
    }
  }

  var iconColor: Color {
    switch self {
    case .home:
      Color(red: 0.55, green: 0.55, blue: 0.58)
    case .dictionary:
      Color(red: 0.44, green: 0.32, blue: 0.90)
    case .snippets:
      Color(red: 0.44, green: 0.32, blue: 0.90)
    case .sounds:
      Color(red: 0.96, green: 0.36, blue: 0.42)
    case .account:
      Color(red: 0.24, green: 0.58, blue: 1.0)
    }
  }
}

struct TabsView: View {
  @State private var currentTab: Tabs

  private let deepLinkCoordinator = RedeemDeepLinkCoordinator.shared

  private let minimumSettingsWidth: CGFloat = 740
  private let minimumSettingsHeight: CGFloat = 420

  init(initialTab: Tabs = .home) {
    _currentTab = State(initialValue: initialTab)
//    UINavigationBar.appearance().largeTitleTextAttributes = [.font : UIFont(name: "Georgia-Bold", size: 20)!]
//
  }
  
  func tabIcon(tab: Tabs) -> some View {
    Image(systemName: currentTab == tab ? tab.selectedSystemImage : tab.systemImage)
      .font(.system(size: 11, weight: .medium))
      .foregroundStyle(.white)
      .frame(width: 20, height: 20)
      .background(
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(
            LinearGradient(
              colors: [tab.iconColor, tab.iconColor.opacity(0.7)],
              startPoint: .top,
              endPoint: .bottom
            )
          )
      )
  }
  
  var body: some View {
    NavigationSplitView {
      VStack(alignment: .leading, spacing: 4) {
        ForEach(Tabs.allCases, id: \.self) { tab in
          Label {
            Text(tab.title)
              .foregroundStyle(currentTab == tab ? .white : .secondary)
          } icon: {
            tabIcon(tab: tab)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 6)
          .padding(.horizontal, 8)
          .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .fill(currentTab == tab ? Color.white.opacity(0.1) : Color.clear)
          )
          .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          .onTapGesture {
            currentTab = tab
          }
        }
        Spacer()
      }
      .padding(.horizontal, 8)
      .toolbar(removing: .sidebarToggle)
    } detail: {
      ScrollView {
        selectedTabView
      }
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
    .navigationTitle("")
    .toolbar {
      ToolbarItem(placement: .navigation) {
        Text(currentTab.title)
          .padding(.leading, 8)
          .font(.title2)
          .fontWeight(.ultraLight)
      }
      .sharedBackgroundVisibility(.hidden)
    }
  }

  @ViewBuilder
  private var selectedTabView: some View {
    switch currentTab {
    case .home:
      GeneralTabView()
    case .dictionary:
      DictionaryTabView()
    case .snippets:
      SnippetsTabView()
    case .sounds:
      SoundsTabView()
    case .account:
      AccountTabView()
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

