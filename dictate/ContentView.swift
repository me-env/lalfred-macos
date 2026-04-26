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
      ShortcutInput().padding(.vertical)
      APIKeyInput().padding(.vertical)
    }
    .padding()
    .textFieldStyle(.roundedBorder)
  }
}

enum Tabs {
  case home
  case models
}

struct TabsView: View {
  @State var currentTab: Tabs = .home
  
  var body: some View {
    TabView(selection: $currentTab) {
      GeneralTabView()
        .tabItem {
          Text("Home")
          Image(systemName: currentTab == .home ? "house.fill" : "house")
        }
        .tag(Tabs.home)
      
      GeneralTabView()
        .tabItem {
          Text("Models")
          Image(systemName: currentTab == .models ? "book.fill" : "book")
        }
        .tag(Tabs.models)
    }

    .tabViewStyle(.sidebarAdaptable)
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
