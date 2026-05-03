import Foundation

enum HotKeyIDAllocator {
  private static let lock = NSLock()
  private static var nextID: UInt32 = 1

  static func next() -> UInt32 {
    lock.lock()
    defer { lock.unlock() }

    let id = nextID
    nextID &+= 1
    if nextID == 0 {
      nextID = 1
    }
    return id
  }
}
