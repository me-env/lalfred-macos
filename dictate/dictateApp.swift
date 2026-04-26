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

  var body: some Scene {
    WindowGroup {
      ContentView()
        .onAppear {
          runtimeCoordinator.start()
        }
    }
  }
}
