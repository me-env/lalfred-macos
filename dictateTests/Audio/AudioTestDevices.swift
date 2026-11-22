import CoreAudio
@testable import L_Alfred

enum AudioTestDevices {
  static let internalMic = InputDevice(id: 1, uid: "internal", name: "MacBook Pro Microphone", transport: .builtIn, isInternalMic: true, isAlive: true)
  static let jackMic = InputDevice(id: 2, uid: "jack", name: "External Microphone", transport: .builtIn, isInternalMic: false, isAlive: true)
  static let airPods = InputDevice(id: 3, uid: "airpods", name: "AirPods Pro", transport: .bluetooth, isInternalMic: false, isAlive: true)
  static let loopback = InputDevice(id: 5, uid: "loopback", name: "BlackHole 2ch", transport: .virtual, isInternalMic: false, isAlive: true)
  static let usbMic = InputDevice(id: 4, uid: "usb", name: "Yeti", transport: .other, isInternalMic: false, isAlive: true)

  static func dead(_ device: InputDevice) -> InputDevice {
    InputDevice(id: device.id, uid: device.uid, name: device.name, transport: device.transport, isInternalMic: device.isInternalMic, isAlive: false)
  }
}
