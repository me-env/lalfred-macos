//
//  dictateApp.swift
//  dictate
//
//  Created by Cyprien Ricque on 4/26/26.
//

import SwiftUI

@main
struct dictateApp: App {
  @State private var runtimeCoordinator = AppRuntimeCoordinator()
  @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true

  init() {
    runtimeCoordinator.start()
  }

  var body: some Scene {
    Settings {
      ContentView()
    }
    MenuBarExtra("ELDictate", image: "MenuBarIcon", isInserted: $showMenuBarExtra) {
      StatusMenu()
    }
  }
  
}
