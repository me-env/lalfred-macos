import Foundation
import IOKit

nonisolated enum ClamshellState {
  /// True when a laptop's lid is closed. Desktops have no lid and report false.
  static func isLidClosed() -> Bool {
    let rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
    guard rootDomain != IO_OBJECT_NULL else { return false }
    defer { IOObjectRelease(rootDomain) }
    let state = IORegistryEntryCreateCFProperty(rootDomain, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)
    return (state?.takeRetainedValue() as? Bool) ?? false
  }
}
