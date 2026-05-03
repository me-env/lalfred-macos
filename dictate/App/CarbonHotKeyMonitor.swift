import Foundation
import Carbon.HIToolbox

final class CarbonHotKeyMonitor {
  private let hotKeyID: EventHotKeyID
  private let shortcutProvider: () -> Shortcut?
  private let onKeyDown: @MainActor () -> Void
  private let onKeyUp: (@MainActor () -> Void)?
  private let reloadOnShortcutChange: Bool
  
  private var hotKeyRef: EventHotKeyRef?
  private var eventHandlerRef: EventHandlerRef?
  
  init(
    signature: OSType = OSType(0x44494354), // 'DICT'
    id: UInt32 = HotKeyIDAllocator.next(),
    shortcutProvider: @escaping () -> Shortcut?,
    reloadOnShortcutChange: Bool = false,
    onKeyDown: @escaping @MainActor () -> Void,
    onKeyUp: (@MainActor () -> Void)? = nil
  ) {
    self.hotKeyID = EventHotKeyID(signature: signature, id: id)
    self.shortcutProvider = shortcutProvider
    self.onKeyDown = onKeyDown
    self.onKeyUp = onKeyUp
    self.reloadOnShortcutChange = reloadOnShortcutChange
    
    installHandlerIfNeeded()
    
    if reloadOnShortcutChange {
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(handleShortcutChange),
        name: .shortcutDidChange,
        object: nil
      )
    }
  }
  
  deinit {
    if reloadOnShortcutChange {
      NotificationCenter.default.removeObserver(self)
    }
    deactivate()
    if let eventHandlerRef {
      RemoveEventHandler(eventHandlerRef)
    }
  }
  
  func activate() {
    guard hotKeyRef == nil else { return }
    guard let shortcut = shortcutProvider() else { return }
    let status = RegisterEventHotKey(
      UInt32(shortcut.keyCode),
      shortcut.carbonModifiers,
      hotKeyID,
      GetApplicationEventTarget(),
      0,
      &hotKeyRef
    )
    
    if status != noErr {
      hotKeyRef = nil
      print("Failed to register hot key (\(hotKeyID.id)): \(status)")
    }
  }
  
  func deactivate() {
    if let hotKeyRef {
      UnregisterEventHotKey(hotKeyRef)
      self.hotKeyRef = nil
    }
  }
  
  @objc private func handleShortcutChange() {
    deactivate()
    activate()
  }
  
  private func installHandlerIfNeeded() {
    guard eventHandlerRef == nil else { return }
    
    var eventSpecs = [
      EventTypeSpec(
        eventClass: OSType(kEventClassKeyboard),
        eventKind: UInt32(kEventHotKeyPressed)
      )
    ]
    if onKeyUp != nil {
      eventSpecs.append(
        EventTypeSpec(
          eventClass: OSType(kEventClassKeyboard),
          eventKind: UInt32(kEventHotKeyReleased)
        )
      )
    }
    
    let selfPointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
    _ = eventSpecs.withUnsafeMutableBufferPointer { specsBuffer in
      InstallEventHandler(
        GetApplicationEventTarget(),
        { _, event, userData in
          guard let event,
                let userData else {
            return noErr
          }
          
          let monitor = Unmanaged<CarbonHotKeyMonitor>.fromOpaque(userData).takeUnretainedValue()
          
          var receivedID = EventHotKeyID()
          let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &receivedID
          )
          
          guard status == noErr,
                receivedID.id == monitor.hotKeyID.id,
                receivedID.signature == monitor.hotKeyID.signature else {
            return OSStatus(eventNotHandledErr)
          }
          
          let eventKind = GetEventKind(event)
          Task { @MainActor in
            if eventKind == UInt32(kEventHotKeyPressed) {
              monitor.onKeyDown()
            } else if eventKind == UInt32(kEventHotKeyReleased) {
              monitor.onKeyUp?()
            }
          }
          return noErr
        },
        specsBuffer.count,
        specsBuffer.baseAddress,
        selfPointer,
        &eventHandlerRef
      )
    }
  }
}
