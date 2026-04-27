//
//  PreferencesInput.swift
//  dictate
//
//  Created by Cyprien Ricque on 4/27/26.
//

import SwiftUI

struct PreferencesInput: View {
  @AppStorage("launchAtLogin") private var launchAtLogin = false
  @AppStorage("autoCheckForUpdates") private var autoCheckForUpdates = false
  
  var body: some View {
    SectionBox("Preferences") {
      Toggle("Launch at login", isOn: $launchAtLogin)
      Toggle("Automatically check for updates", isOn: $autoCheckForUpdates)
    }
  }
}
