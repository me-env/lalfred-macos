//
//  LaunchAtLoginService.swift
//  dictate
//
//  Created by Codex on 4/27/26.
//

import Foundation
import ServiceManagement

struct LaunchAtLoginService {
  private let service: SMAppService
  
  init(service: SMAppService = .mainApp) {
    self.service = service
  }
  
  func isEnabledInSystem() -> Bool {
    switch service.status {
    case .enabled, .requiresApproval:
      return true
    default:
      return false
    }
  }
  
  func synchronizeStoredPreference(
    defaults: UserDefaults = .standard,
    key: String = AppDefaultsKey.launchAtLogin
  ) {
    defaults.set(isEnabledInSystem(), forKey: key)
  }
  
  func setEnabled(_ enabled: Bool) throws {
    if enabled {
      try registerIfNeeded()
    } else {
      try unregisterIfNeeded()
    }
  }
  
  func openLoginItemsSettings() {
    SMAppService.openSystemSettingsLoginItems()
  }
  
  private func registerIfNeeded() throws {
    do {
      try service.register()
    } catch {
      if isServiceManagementError(error, code: kSMErrorAlreadyRegistered) {
        return
      }
      throw error
    }
  }
  
  private func unregisterIfNeeded() throws {
    do {
      try service.unregister()
    } catch {
      if isServiceManagementError(error, code: kSMErrorJobNotFound) {
        return
      }
      throw error
    }
  }
  
  private func isServiceManagementError(_ error: Error, code: Int) -> Bool {
    let nsError = error as NSError
    return nsError.domain == SMAppServiceErrorDomain && nsError.code == code
  }
}
