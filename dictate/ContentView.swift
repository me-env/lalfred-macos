//
//  ContentView.swift
//  dictate
//
//  Created by Cyprien Ricque on 4/26/26.
//

import SwiftUI


struct GeneralTabView: View {
  var body: some View {
    VStack {
      PreferencesInput()
      ShortcutInput()
      PermissionsInput()
      APIKeyInput()
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
}

struct TabsView: View {
  @State var currentTab: Tabs = .home
  
  var body: some View {
    TabView(selection: $currentTab) {
      GeneralTabView()
        .tabItem {
          Text("General")
          Image(systemName: currentTab == .home ? "gearshape.fill" : "gearshape")
        }
        .tag(Tabs.home)
      
      DictionaryTabView()
        .tabItem {
          Text("Dictionary")
          Image(systemName: currentTab == .dictionary ? "book.fill" : "book")
        }
        .tag(Tabs.dictionary)
    }
    .tabViewStyle(.tabBarOnly)
    .navigationTitle("Dictate")
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
