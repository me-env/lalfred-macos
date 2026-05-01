//
//  PreferencesInput.swift
//  dictate
//
//  Created by Cyprien Ricque on 4/27/26.
//

import SwiftUI

struct PreferencesInput: View {
  @AppStorage("launchAtLogin") private var launchAtLogin = false
  @State private var launchAtLoginErrorMessage: String?
  private let launchAtLoginService = LaunchAtLoginService()
  
  var body: some View {
    SectionBox("Preferences") {
      Toggle("Launch at login", isOn: Binding(
        get: { launchAtLogin },
        set: { newValue in
          updateLaunchAtLogin(newValue)
        }
      ))
    }
    .onAppear {
      launchAtLogin = launchAtLoginService.isEnabledInSystem()
    }
    .alert(
      "Unable to update Launch at login",
      isPresented: Binding(
        get: { launchAtLoginErrorMessage != nil },
        set: { isPresented in
          if !isPresented {
            launchAtLoginErrorMessage = nil
          }
        }
      )
    ) {
      Button("Open Login Items") {
        launchAtLoginService.openLoginItemsSettings()
      }
      Button("OK", role: .cancel) {}
    } message: {
      Text(launchAtLoginErrorMessage ?? "Please try again.")
    }
  }

  private func updateLaunchAtLogin(_ newValue: Bool) {
    let previousValue = launchAtLogin
    launchAtLogin = newValue

    do {
      try launchAtLoginService.setEnabled(newValue)
      launchAtLogin = launchAtLoginService.isEnabledInSystem()
    } catch {
      launchAtLogin = previousValue
      launchAtLoginErrorMessage = error.localizedDescription
    }
  }
}
