import AVFoundation
import CoreAudio

/// Reads the CoreAudio properties recording needs.
nonisolated enum AudioDevices {
  static func defaultInput() -> AudioDeviceID? {
    defaultDevice(kAudioHardwarePropertyDefaultInputDevice)
  }

  /// Every device with an input stream.
  static func inputDevices() -> [InputDevice] {
    allDeviceIDs().compactMap(inputDevice)
  }

  /// Unmutes the device's input, when it has a mute control.
  static func clearInputMute(_ device: AudioDeviceID) {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyMute,
      mScope: kAudioObjectPropertyScopeInput,
      mElement: kAudioObjectPropertyElementMain
    )
    var isSettable: DarwinBoolean = false
    guard AudioObjectHasProperty(device, &address),
          AudioObjectIsPropertySettable(device, &address, &isSettable) == noErr, isSettable.boolValue else {
      return
    }
    var isMuted: UInt32 = 0
    AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &isMuted)
  }

  /// A Bluetooth headset whose mic no app is using, and whose playback still runs at a music-mode
  /// sample rate, has to switch to headset mode before its mic delivers audio. Right after a
  /// recording the headset is still in headset mode (same rate as the mic) and needs no switch.
  static func needsHeadsetSwitch(_ inputDevice: AudioDeviceID) -> Bool {
    var isRunningSomewhere: UInt32 = 0
    guard isBluetooth(inputDevice),
          readProperty(inputDevice, kAudioDevicePropertyDeviceIsRunningSomewhere, into: &isRunningSomewhere) == noErr,
          isRunningSomewhere == 0,
          let outputDevice = defaultDevice(kAudioHardwarePropertyDefaultOutputDevice) else {
      return false
    }
    return nominalSampleRate(of: outputDevice) != nominalSampleRate(of: inputDevice)
  }

  /// The format of the device's first input stream, as an IOProc receives it. For a stream with
  /// separate channel buffers, only the first channel is used.
  static func inputFormat(of device: AudioDeviceID) -> AVAudioFormat? {
    var stream = AudioStreamID(kAudioObjectUnknown)
    guard readProperty(device, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput, into: &stream) == noErr,
          stream != kAudioObjectUnknown else {
      return nil
    }

    var description = AudioStreamBasicDescription()
    guard readProperty(stream, kAudioStreamPropertyVirtualFormat, into: &description) == noErr,
          description.mSampleRate > 0, description.mChannelsPerFrame > 0,
          let format = AVAudioFormat(streamDescription: &description) else {
      return nil
    }

    guard !format.isInterleaved, format.channelCount > 1 else { return format }
    return AVAudioFormat(commonFormat: format.commonFormat, sampleRate: format.sampleRate, channels: 1, interleaved: false)
  }

  private static func inputDevice(_ device: AudioDeviceID) -> InputDevice? {
    guard hasInputStream(device), let uid = stringProperty(device, kAudioDevicePropertyDeviceUID) else { return nil }
    let transport = transport(of: device)
    var isAlive: UInt32 = 0
    _ = readProperty(device, kAudioDevicePropertyDeviceIsAlive, into: &isAlive)
    return InputDevice(
      id: device,
      uid: uid,
      name: stringProperty(device, kAudioObjectPropertyName) ?? uid,
      transport: transport,
      isInternalMic: transport == .builtIn && !isExternalBuiltInInput(device),
      isAlive: isAlive != 0
    )
  }

  private static func allDeviceIDs() -> [AudioDeviceID] {
    let system = AudioObjectID(kAudioObjectSystemObject)
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDevices,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return [] }
    var devices = [AudioDeviceID](repeating: kAudioObjectUnknown, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else { return [] }
    return devices
  }

  private static func hasInputStream(_ device: AudioDeviceID) -> Bool {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyStreams,
      mScope: kAudioObjectPropertyScopeInput,
      mElement: kAudioObjectPropertyElementMain
    )
    var size: UInt32 = 0
    return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
  }

  private static func transport(of device: AudioDeviceID) -> InputDevice.Transport {
    var transportType: UInt32 = 0
    guard readProperty(device, kAudioDevicePropertyTransportType, into: &transportType) == noErr else { return .other }
    switch transportType {
    case kAudioDeviceTransportTypeBuiltIn: return .builtIn
    case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return .bluetooth
    case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate: return .virtual
    default: return .other
    }
  }

  /// A built-in input whose data source is the headphone jack ('emic') rather than the internal mic.
  private static func isExternalBuiltInInput(_ device: AudioDeviceID) -> Bool {
    var dataSource: UInt32 = 0
    let status = readProperty(device, kAudioDevicePropertyDataSource, scope: kAudioObjectPropertyScopeInput, into: &dataSource)
    return status == noErr && dataSource == externalMicDataSource
  }

  /// 'emic'
  private static let externalMicDataSource: UInt32 = 0x656D_6963

  private static func stringProperty(_ objectID: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
    return value.takeRetainedValue() as String
  }

  private static func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioDeviceID? {
    var deviceID = AudioDeviceID(kAudioObjectUnknown)
    let status = readProperty(AudioObjectID(kAudioObjectSystemObject), selector, into: &deviceID)
    guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
    return deviceID
  }

  private static func nominalSampleRate(of device: AudioDeviceID) -> Float64 {
    var sampleRate: Float64 = 0
    _ = readProperty(device, kAudioDevicePropertyNominalSampleRate, into: &sampleRate)
    return sampleRate
  }

  private static func isBluetooth(_ device: AudioDeviceID) -> Bool {
    transport(of: device) == .bluetooth
  }

  private static func readProperty<Value: BitwiseCopyable>(
    _ objectID: AudioObjectID,
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
    into value: inout Value
  ) -> OSStatus {
    var size = UInt32(MemoryLayout<Value>.size)
    var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    return AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value)
  }
}
