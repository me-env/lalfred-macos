import Accelerate

/// Measures how much of the latest audio falls in each voice band. The bands split 100 Hz...8 kHz
/// on a log scale. Samples are only copied as they arrive; the FFT runs when a level is reported.
/// Every buffer is allocated up front, so it is safe on the capture callback queue.
nonisolated final class VoiceSpectrumAnalyzer {
  /// 32 ms at 16 kHz, about one report interval.
  static let frameLength = 512
  static let bandEdgesHertz: [Float] = [100, 208, 431, 894, 1856, 3852, 8000]
  private static let log2FrameLength = vDSP_Length(9)
  private static let binCount = frameLength / 2

  private let fftSetup: FFTSetup
  /// Hann window, also scaling Int16 samples to -1...1.
  private let window: UnsafeMutableBufferPointer<Float>
  /// The latest `frameLength` samples, oldest at `nextWriteIndex`.
  private let recentSamples: UnsafeMutableBufferPointer<Float>
  private var nextWriteIndex = 0
  private let frame: UnsafeMutableBufferPointer<Float>
  private let real: UnsafeMutableBufferPointer<Float>
  private let imaginary: UnsafeMutableBufferPointer<Float>
  private let binPowers: UnsafeMutableBufferPointer<Float>
  private let bandBins: [Range<Int>]
  /// Turns a sum of vDSP bin magnitudes into a mean square, so a sine reads like its RMS.
  private let powerScale: Float

  init(sampleRate: Float = Float(TranscriptionAudio.sampleRate)) {
    guard let fftSetup = vDSP_create_fftsetup(Self.log2FrameLength, FFTRadix(kFFTRadix2)) else {
      fatalError("vDSP could not create a \(Self.frameLength)-point FFT setup")
    }
    self.fftSetup = fftSetup
    window = Self.allocateZeroed(Self.frameLength)
    recentSamples = Self.allocateZeroed(Self.frameLength)
    frame = Self.allocateZeroed(Self.frameLength)
    real = Self.allocateZeroed(Self.binCount)
    imaginary = Self.allocateZeroed(Self.binCount)
    binPowers = Self.allocateZeroed(Self.binCount)
    bandBins = Self.bandBins(sampleRate: sampleRate)
    powerScale = Self.fillWindow(window)
  }

  deinit {
    vDSP_destroy_fftsetup(fftSetup)
    [window, recentSamples, frame, real, imaginary, binPowers].forEach { $0.deallocate() }
  }

  func append(_ samples: UnsafeBufferPointer<Int16>) {
    guard let base = samples.baseAddress else { return }
    let keptCount = min(samples.count, Self.frameLength)
    let kept = base + (samples.count - keptCount)
    let firstCount = min(keptCount, Self.frameLength - nextWriteIndex)
    vDSP_vflt16(kept, 1, recentSamples.baseAddress! + nextWriteIndex, 1, vDSP_Length(firstCount))
    vDSP_vflt16(kept + firstCount, 1, recentSamples.baseAddress!, 1, vDSP_Length(keptCount - firstCount))
    nextWriteIndex = (nextWriteIndex + keptCount) % Self.frameLength
  }

  /// The power in each band of the latest frame, in dBFS; lanes past the bands are unused.
  func bandDecibels() -> SIMD8<Float> {
    copyWindowedFrame()
    computeBinPowers()
    var decibels = SIMD8<Float>(repeating: SpeechLevelNormalizer.silenceDecibels)
    for (band, bins) in bandBins.enumerated() {
      decibels[band] = Self.decibels(ofMeanSquare: sum(of: bins) * powerScale)
    }
    return decibels
  }

  /// Unrolls the ring buffer oldest first, then applies the window.
  private func copyWindowedFrame() {
    let olderCount = Self.frameLength - nextWriteIndex
    frame.baseAddress!.update(from: recentSamples.baseAddress! + nextWriteIndex, count: olderCount)
    (frame.baseAddress! + olderCount).update(from: recentSamples.baseAddress!, count: nextWriteIndex)
    vDSP_vmul(frame.baseAddress!, 1, window.baseAddress!, 1, frame.baseAddress!, 1, vDSP_Length(Self.frameLength))
  }

  private func computeBinPowers() {
    var split = DSPSplitComplex(realp: real.baseAddress!, imagp: imaginary.baseAddress!)
    frame.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: Self.binCount) { pairs in
      vDSP_ctoz(pairs, 2, &split, 1, vDSP_Length(Self.binCount))
    }
    vDSP_fft_zrip(fftSetup, &split, 1, Self.log2FrameLength, FFTDirection(FFT_FORWARD))
    // Holds the packed Nyquist bin; no band uses bin 0.
    imaginary[0] = 0
    vDSP_zvmags(&split, 1, binPowers.baseAddress!, 1, vDSP_Length(Self.binCount))
  }

  private func sum(of bins: Range<Int>) -> Float {
    var total: Float = 0
    vDSP_sve(binPowers.baseAddress! + bins.lowerBound, 1, &total, vDSP_Length(bins.count))
    return total
  }

  private static func decibels(ofMeanSquare meanSquare: Float) -> Float {
    10 * log10(max(meanSquare, 1e-10))
  }

  /// A bin belongs to the band its center frequency falls in.
  private static func bandBins(sampleRate: Float) -> [Range<Int>] {
    let binHertz = sampleRate / Float(frameLength)
    let edgeBins = bandEdgesHertz.map { min(Int(($0 / binHertz).rounded(.up)), binCount) }
    return zip(edgeBins, edgeBins.dropFirst()).map { $0..<max($1, $0 + 1) }
  }

  /// Fills a Hann window scaled for Int16 input; returns the matching power scale.
  private static func fillWindow(_ window: UnsafeMutableBufferPointer<Float>) -> Float {
    vDSP_hann_window(window.baseAddress!, vDSP_Length(frameLength), Int32(vDSP_HANN_DENORM))
    var windowMeanSquare: Float = 0
    vDSP_measqv(window.baseAddress!, 1, &windowMeanSquare, vDSP_Length(frameLength))
    var sampleScale = 1 / Float(Int16.max)
    vDSP_vsmul(window.baseAddress!, 1, &sampleScale, window.baseAddress!, 1, vDSP_Length(frameLength))
    // vDSP's forward FFT doubles the DFT; one-sided bins count twice.
    let length = Float(frameLength)
    return 2 / (4 * length * length * windowMeanSquare)
  }

  private static func allocateZeroed(_ count: Int) -> UnsafeMutableBufferPointer<Float> {
    let buffer = UnsafeMutableBufferPointer<Float>.allocate(capacity: count)
    buffer.initialize(repeating: 0)
    return buffer
  }
}
