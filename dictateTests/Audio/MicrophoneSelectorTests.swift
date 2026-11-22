import CoreAudio
import Testing
@testable import L_Alfred

struct MicrophoneSelectorTests {
  private typealias Devices = AudioTestDevices

  private func select(
    _ devices: [InputDevice],
    systemDefault: AudioDeviceID?,
    preferences: MicrophonePreferences = MicrophonePreferences(),
    isLidClosed: Bool = false,
    excluding excludedUIDs: Set<String> = []
  ) -> InputDevice? {
    MicrophoneSelector.select(in: MicrophoneSelector.Context(
      devices: devices,
      systemDefault: systemDefault,
      preferences: preferences,
      isLidClosed: isLidClosed,
      excludedUIDs: excludedUIDs
    ))
  }

  private func priorityList(_ devices: [InputDevice]) -> MicrophonePreferences {
    var preferences = MicrophonePreferences().remembering(devices)
    preferences.mode = .priorityList
    return preferences
  }

  @Test func systemDefaultModeReturnsTheDefaultInput() {
    #expect(select([Devices.internalMic, Devices.usbMic], systemDefault: Devices.usbMic.id) == Devices.usbMic)
  }

  @Test func bluetoothDefaultIsAvoidedForTheBuiltInMic() {
    #expect(select([Devices.internalMic, Devices.airPods], systemDefault: Devices.airPods.id) == Devices.internalMic)
  }

  @Test func bluetoothDefaultIsKeptWhenAvoidanceIsOff() {
    var preferences = MicrophonePreferences()
    preferences.avoidBluetoothMicrophone = false
    #expect(select([Devices.internalMic, Devices.airPods], systemDefault: Devices.airPods.id, preferences: preferences) == Devices.airPods)
  }

  @Test func closedLidSkipsTheInternalMicButNotTheJackMic() {
    #expect(select([Devices.internalMic, Devices.jackMic], systemDefault: Devices.internalMic.id, isLidClosed: true) == Devices.jackMic)
  }

  @Test func closedLidKeepsTheInternalMicWhenItIsTheOnlyInput() {
    #expect(select([Devices.internalMic], systemDefault: Devices.internalMic.id, isLidClosed: true) == Devices.internalMic)
  }

  @Test func closedLidWithBluetoothDefaultKeepsTheBluetoothMic() {
    #expect(select([Devices.internalMic, Devices.airPods], systemDefault: Devices.airPods.id, isLidClosed: true) == Devices.airPods)
  }

  @Test func priorityListReturnsTheFirstConnectedMicrophone() {
    let preferences = priorityList([Devices.usbMic, Devices.airPods, Devices.internalMic])
    #expect(select([Devices.internalMic, Devices.airPods], systemDefault: Devices.internalMic.id, preferences: preferences) == Devices.airPods)
  }

  @Test func priorityListWithNoneConnectedFollowsTheSystemDefault() {
    let preferences = priorityList([Devices.usbMic])
    #expect(select([Devices.internalMic, Devices.jackMic], systemDefault: Devices.jackMic.id, preferences: preferences) == Devices.jackMic)
  }

  @Test func excludedMicrophonesAreNeverReturned() {
    let preferences = priorityList([Devices.usbMic, Devices.internalMic])
    #expect(select([Devices.internalMic, Devices.usbMic], systemDefault: Devices.usbMic.id, preferences: preferences, excluding: ["usb"]) == Devices.internalMic)
  }

  @Test func deadMicrophonesAreNeverReturned() {
    #expect(select([Devices.internalMic, Devices.dead(Devices.usbMic)], systemDefault: Devices.usbMic.id) == Devices.internalMic)
  }

  @Test func missingDefaultFallsBackToTheBuiltInMicThenToAnyInput() {
    #expect(select([Devices.usbMic, Devices.internalMic], systemDefault: nil) == Devices.internalMic)
    #expect(select([Devices.usbMic, Devices.airPods], systemDefault: nil) == Devices.usbMic)
    #expect(select([], systemDefault: nil) == nil)
  }

  @Test func fallbackPrefersAMicrophoneOverALoopbackDevice() {
    #expect(select([Devices.loopback, Devices.usbMic], systemDefault: nil) == Devices.usbMic)
    #expect(select([Devices.loopback], systemDefault: nil) == Devices.loopback)
  }

  @Test func loopbackChosenAsSystemDefaultIsHonored() {
    #expect(select([Devices.loopback, Devices.usbMic], systemDefault: Devices.loopback.id) == Devices.loopback)
  }
}
