import AppKit
import Carbon.HIToolbox
import Foundation
import Observation

private final class LocalKeyDownMonitor {
  private var monitorToken: Any?

  func start(handler: @escaping (NSEvent) -> Bool) {
    guard monitorToken == nil else { return }

    monitorToken = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      handler(event) ? nil : event
    }
  }

  func stop() {
    guard let monitorToken else { return }
    NSEvent.removeMonitor(monitorToken)
    self.monitorToken = nil
  }

  deinit {
    stop()
  }
}

private final class LocalFlagsChangedMonitor {
  private var monitorToken: Any?

  func start(handler: @escaping (NSEvent) -> Bool) {
    guard monitorToken == nil else { return }

    monitorToken = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
      handler(event) ? nil : event
    }
  }

  func stop() {
    guard let monitorToken else { return }
    NSEvent.removeMonitor(monitorToken)
    self.monitorToken = nil
  }

  deinit {
    stop()
  }
}

@Observable
final class ShortcutRecorder {
  let id: String
  private(set) var shortcut: Shortcut?
  private(set) var isCapturing: Bool = false

  @ObservationIgnored private let defaultShortcut: Shortcut
  @ObservationIgnored private let store: ShortcutDefaultsStore
  @ObservationIgnored private var pendingModifiers: ShortcutModifiers = []
  @ObservationIgnored private let keyDownMonitor = LocalKeyDownMonitor()
  @ObservationIgnored private let flagsChangedMonitor = LocalFlagsChangedMonitor()

  init(
    id: String,
    defaultShortcut: Shortcut,
    userDefaults: UserDefaults = .standard
  ) {
    self.id = id
    self.defaultShortcut = defaultShortcut
    self.store = ShortcutDefaultsStore(key: id, userDefaults: userDefaults)
    self.store.ensureDefault(defaultShortcut)
    self.shortcut = self.store.load()
  }

  deinit {
    keyDownMonitor.stop()
    flagsChangedMonitor.stop()
  }

  func begin() {
    guard !isCapturing else { return }
    pendingModifiers = []
    isCapturing = true
    keyDownMonitor.start { [weak self] event in
      self?.handleKeyDown(event) ?? false
    }
    flagsChangedMonitor.start { [weak self] event in
      self?.handleFlagsChanged(event) ?? false
    }
    publishCaptureState(true)
  }

  func cancel() {
    guard isCapturing else { return }
    pendingModifiers = []
    shortcut = store.load()
    stopCapture()
  }

  func clear() {
    pendingModifiers = []
    shortcut = nil
    store.remove()
    stopCapture()
    NotificationCenter.default.post(name: .shortcutDidChange, object: nil)
  }

  func restoreDefault() {
    pendingModifiers = []
    shortcut = defaultShortcut
    store.save(defaultShortcut)
    stopCapture()
    NotificationCenter.default.post(name: .shortcutDidChange, object: nil)
  }

  private func finishCapture(saving newShortcut: Shortcut) {
    pendingModifiers = []
    shortcut = newShortcut
    store.save(newShortcut)
    stopCapture()
    NotificationCenter.default.post(name: .shortcutDidChange, object: nil)
  }

  private func stopCapture() {
    keyDownMonitor.stop()
    flagsChangedMonitor.stop()
    guard isCapturing else { return }
    isCapturing = false
    publishCaptureState(false)
  }

  private func publishCaptureState(_ isCapturing: Bool) {
    NotificationCenter.default.post(
      name: .shortcutCaptureStateDidChange,
      object: nil,
      userInfo: [ShortcutNotificationUserInfoKey.isCapturing: isCapturing]
    )
  }

  private func handleKeyDown(_ event: NSEvent) -> Bool {
    guard isCapturing else { return false }

    if event.keyCode == UInt16(kVK_Escape) {
      cancel()
      return true
    }

    if Self.modifierKeyCodes.contains(event.keyCode) {
      return true
    }

    let newShortcut = Shortcut(
      keyCode: event.keyCode,
      modifiers: ShortcutModifiers(eventModifierFlags: event.modifierFlags)
    )
    finishCapture(saving: newShortcut)
    return true
  }

  private func handleFlagsChanged(_ event: NSEvent) -> Bool {
    guard isCapturing else { return false }

    let modifiers = ShortcutModifiers(eventModifierFlags: event.modifierFlags)

    if modifiers.count >= 2 {
      pendingModifiers = modifiers
      shortcut = Shortcut(keyCode: Shortcut.modifierOnlyKeyCode, modifiers: modifiers)
      return true
    }

    if !pendingModifiers.isEmpty && modifiers.isEmpty {
      finishCapture(
        saving: Shortcut(keyCode: Shortcut.modifierOnlyKeyCode, modifiers: pendingModifiers)
      )
      return true
    }

    return true
  }

  private static let modifierKeyCodes: Set<UInt16> = [
    UInt16(kVK_Command),
    UInt16(kVK_RightCommand),
    UInt16(kVK_Shift),
    UInt16(kVK_RightShift),
    UInt16(kVK_Option),
    UInt16(kVK_RightOption),
    UInt16(kVK_Control),
    UInt16(kVK_RightControl),
    UInt16(kVK_CapsLock),
    UInt16(kVK_Function)
  ]
}
