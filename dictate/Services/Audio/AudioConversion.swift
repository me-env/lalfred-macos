import AVFoundation

/// Converts device buffers to ``AudioRecordingService/outputFormat``.
nonisolated enum AudioConversion {
  static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter) -> Data? {
    let ratio = AudioRecordingService.outputFormat.sampleRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16

    var didProvideInput = false
    return run(converter, capacity: capacity) { inputStatus in
      if didProvideInput {
        inputStatus.pointee = .noDataNow
        return nil
      }
      didProvideInput = true
      inputStatus.pointee = .haveData
      return buffer
    }
  }

  /// Returns the samples the resampler still holds once no more input will come.
  static func drain(_ converter: AVAudioConverter) -> Data? {
    run(converter, capacity: 1024) { inputStatus in
      inputStatus.pointee = .endOfStream
      return nil
    }
  }

  private static func run(
    _ converter: AVAudioConverter,
    capacity: AVAudioFrameCount,
    input: @escaping (UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer?
  ) -> Data? {
    guard let output = AVAudioPCMBuffer(pcmFormat: AudioRecordingService.outputFormat, frameCapacity: capacity) else {
      return nil
    }

    var error: NSError?
    let status = converter.convert(to: output, error: &error) { _, inputStatus in
      input(inputStatus)
    }

    guard status != .error, output.frameLength > 0, let samples = output.int16ChannelData else {
      return nil
    }

    return Data(bytes: samples[0], count: Int(output.frameLength) * MemoryLayout<Int16>.size)
  }
}
