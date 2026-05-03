import Foundation
import Carbon.HIToolbox

final class GlobalHotKeyMonitor {
  private let shortcutStore: ShortcutDefaultsStore
  private let monitor: CarbonHotKeyMonitor
  
  init(
    id: UInt32 = HotKeyIDAllocator.next(),
    storeKey: String,
    defaultShortcut: Shortcut,
    onTrigger: @escaping @MainActor () -> Void
  ) {
    self.shortcutStore = ShortcutDefaultsStore(key: storeKey)
    shortcutStore.ensureDefault(defaultShortcut)
    
    monitor = CarbonHotKeyMonitor(
      id: id,
      shortcutProvider: { [shortcutStore] in
        shortcutStore.load()
      },
      reloadOnShortcutChange: true,
      onKeyDown: onTrigger
    )
    monitor.activate()
  }
  
  func activate() {
    monitor.activate()
  }
  
  func deactivate() {
    monitor.deactivate()
  }
  
  deinit {
    monitor.deactivate()
  }
}
