import AVFoundation
import CoreAudio

/// Reads the CoreAudio properties recording needs.
nonisolated enum AudioDevices {
  static func defaultInput() -> AudioDeviceID? {
    defaultDevice(kAudioHardwarePropertyDefaultInputDevice)
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
    var transportType: UInt32 = 0
    return readProperty(device, kAudioDevicePropertyTransportType, into: &transportType) == noErr
      && transportType == kAudioDeviceTransportTypeBluetooth
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
