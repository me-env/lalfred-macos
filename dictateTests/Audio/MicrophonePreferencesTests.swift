import Foundation
import Testing
@testable import L_Alfred

struct MicrophonePreferencesTests {
  private typealias Devices = AudioTestDevices

  @Test func codableRoundTrip() throws {
    var preferences = MicrophonePreferences().remembering([Devices.usbMic, Devices.airPods])
    preferences.mode = .priorityList
    preferences.avoidBluetoothMicrophone = false
    let decoded = try JSONDecoder().decode(MicrophonePreferences.self, from: JSONEncoder().encode(preferences))
    #expect(decoded == preferences)
  }

  @Test func rememberingAppendsNewMicrophonesOnceAndRefreshesNames() {
    let renamed = InputDevice(id: 9, uid: "usb", name: "Yeti X", transport: .other, isInternalMic: false, isAlive: true)
    let preferences = MicrophonePreferences()
      .remembering([Devices.usbMic, Devices.airPods])
      .remembering([Devices.airPods, renamed, Devices.internalMic])
    #expect(preferences.priority.map(\.uid) == ["usb", "airpods", "internal"])
    #expect(preferences.priority.first?.name == "Yeti X")
  }

  @Test func movingReordersWithinBounds() {
    let preferences = MicrophonePreferences().remembering([Devices.usbMic, Devices.airPods, Devices.internalMic])
    #expect(preferences.moving(uid: "internal", by: -1).priority.map(\.uid) == ["usb", "internal", "airpods"])
    #expect(preferences.moving(uid: "usb", by: -1).priority.map(\.uid) == ["usb", "airpods", "internal"])
    #expect(preferences.moving(uid: "usb", by: 5).priority.map(\.uid) == ["airpods", "internal", "usb"])
  }

  @Test func removingForgetsTheMicrophone() {
    let preferences = MicrophonePreferences().remembering([Devices.usbMic, Devices.airPods])
    #expect(preferences.removing(uid: "usb").priority.map(\.uid) == ["airpods"])
  }
}
