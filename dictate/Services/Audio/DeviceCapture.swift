import AVFoundation
import CoreAudio

/// One IOProc on one input device, delivering its buffers to the capture session.
///
/// Captures straight from the input device with a HAL IOProc. `AVAudioEngine` opened a playback
/// stream that collided with a Bluetooth headset's mode switch, and audio queues kept the mic
/// running for seconds after being disposed, which jammed a recording started in that window.
/// The IOProc starts and stops the device immediately, so the mic is released between recordings.
nonisolated final class DeviceCapture: @unchecked Sendable {
  let device: AudioDeviceID
  private let format: AVAudioFormat
  private var procID: AudioDeviceIOProcID?

  /// Only buffers of the session's current `generation` are recorded.
  init(device: AudioDeviceID, generation: Int, session: AudioCaptureSession, queue: DispatchQueue) throws {
    guard let format = AudioDevices.inputFormat(of: device),
          let converter = AVAudioConverter(from: format, to: AudioRecordingService.outputFormat) else {
      throw AudioRecordingService.RecordingError.failedToCreateRecorder
    }
    converter.downmix = true
    self.device = device
    self.format = format

    var procID: AudioDeviceIOProcID?
    let status = AudioDeviceCreateIOProcIDWithBlock(&procID, device, queue) { _, inputData, inputTime, _, _ in
      session.process(inputData, inputTime: inputTime.pointee, generation: generation, format: format, converter: converter)
    }
    guard status == noErr, let procID else {
      throw AudioRecordingService.RecordingError.failedToCreateRecorder
    }
    guard AudioDeviceStart(device, procID) == noErr else {
      AudioDeviceDestroyIOProcID(device, procID)
      throw AudioRecordingService.RecordingError.failedToCreateRecorder
    }
    self.procID = procID
  }

  func matchesCurrentFormat() -> Bool {
    guard let current = AudioDevices.inputFormat(of: device) else { return false }
    return current.sampleRate == format.sampleRate
      && current.channelCount == format.channelCount
      && current.commonFormat == format.commonFormat
      && current.isInterleaved == format.isInterleaved
  }

  /// Stops the device right away; the IOProc is destroyed on `queue`, after any callback already
  /// scheduled there has run.
  func stop(on queue: DispatchQueue) {
    guard let procID else { return }
    AudioDeviceStop(device, procID)
    let device = device
    nonisolated(unsafe) let stoppedProcID = procID
    queue.async {
      AudioDeviceDestroyIOProcID(device, stoppedProcID)
    }
    self.procID = nil
  }
}
