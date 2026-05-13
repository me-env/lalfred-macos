import SwiftUI
import AppKit


struct TabsView: View {
  @State private var currentTab: Tabs

  private let deepLinkCoordinator = RedeemDeepLinkCoordinator.shared

  private let minimumSettingsWidth: CGFloat = 740
  private let minimumSettingsHeight: CGFloat = 420

  init(initialTab: Tabs = .home) {
    _currentTab = State(initialValue: initialTab)
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
              .foregroundStyle(currentTab == tab ? Color.primary : .secondary)
          } icon: {
            tabIcon(tab: tab)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 6)
          .padding(.horizontal, 8)
          .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .fill(currentTab == tab ? Color.secondary.opacity(0.15) : Color.clear)
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

