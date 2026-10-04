import SwiftUI
import AppKit


private struct IgnoredWordsInput: Equatable {
  let wordsData: Data
  let rawProvider: String
}

struct TabsView: View {
  @State private var currentTab: Tabs
  @AppStorage(AppDefaultsKey.savedWords) private var savedWordsData = Data()
  @AppStorage(AppDefaultsKey.transcriptionProvider) private var rawProvider = TranscriptionProvider.defaultProvider.rawValue
  @State private var hasIgnoredWords = false

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
  
  /// Whether the selected provider skips at least one dictionary word, computed off the main thread.
  private func updateHasIgnoredWords() async {
    let provider = TranscriptionProvider(rawValue: rawProvider) ?? .defaultProvider
    let wordsData = savedWordsData
    let hasIgnored = await Task.detached {
      let words = (try? JSONDecoder().decode([String].self, from: wordsData)) ?? []
      return words.contains { provider.ignoredKeytermReason($0) != nil }
    }.value
    guard !Task.isCancelled else { return }
    hasIgnoredWords = hasIgnored
  }

  private func showsWarning(for tab: Tabs) -> Bool {
    tab == .dictionary && hasIgnoredWords
  }

  var body: some View {
    NavigationSplitView {
      VStack(alignment: .leading, spacing: 4) {
        ForEach(Tabs.allCases, id: \.self) { tab in
          Label {
            HStack(spacing: 6) {
              Text(tab.title)
                .foregroundStyle(currentTab == tab ? Color.primary : .secondary)

              if showsWarning(for: tab) {
                Circle()
                  .fill(.orange)
                  .frame(width: 6, height: 6)
                  .help("Some words are ignored by the selected model")
              }
            }
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
        VStack(spacing: 8) {
          PermissionRegressionBanner()
          selectedTabView
        }
      }
    }
    .task(id: IgnoredWordsInput(wordsData: savedWordsData, rawProvider: rawProvider)) {
      await updateHasIgnoredWords()
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
}


struct ContentView: View {
  private let initialTab: Tabs
  @AppStorage(AppDefaultsKey.hasCompletedOnboarding) private var hasCompletedOnboarding = false

  init(initialTab: Tabs = .home) {
    self.initialTab = initialTab
  }

  var body: some View {
    if hasCompletedOnboarding {
      TabsView(initialTab: initialTab)
    } else {
      OnboardingView()
        .frame(minHeight: 550, maxHeight: 560)
    }
  }
}


#Preview("General") {
  ContentView(initialTab: .home)
    .environment(Shortcuts())
}

#Preview("Dictionary") {
  ContentView(initialTab: .dictionary)
    .environment(Shortcuts())
}

#Preview("Snippets") {
  ContentView(initialTab: .snippets)
    .environment(Shortcuts())
}

#Preview("Sounds") {
  ContentView(initialTab: .sounds)
    .environment(Shortcuts())
}

#Preview("Account") {
  ContentView(initialTab: .account)
    .environment(Shortcuts())
}

