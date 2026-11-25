import Foundation
import Testing
@testable import L_Alfred

struct PauseCutPointTests {
  private func pcm(_ samples: [Int16]) -> Data {
    samples.withUnsafeBytes { Data($0) }
  }

  @Test func noCutWhileEveryWindowHoldsSpeech() {
    let audio = pcm([Int16](repeating: 100, count: 16_000))
    let windows = [
      SpeechWindow(samples: 0 ..< 8_000, speechConfidence: 0.9),
      SpeechWindow(samples: 4_000 ..< 12_000, speechConfidence: 0.6),
    ]

    #expect(PauseCutPoint.find(in: windows, audio: audio, audioStart: 0) == nil)
  }

  @Test func cutsOnTheQuietestFrameOfTheFirstPause() {
    var samples = [Int16](repeating: 500, count: 16_000)
    // The quietest 20 ms frame of the first pause window, which starts at 4_000; recording position 11_280.
    for index in 5_280 ..< 5_600 { samples[index] = 1 }
    // A quieter frame in a later pause is not chosen.
    for index in 12_000 ..< 12_320 { samples[index] = 0 }
    let windows = [
      SpeechWindow(samples: 6_000 ..< 14_000, speechConfidence: 0.9),
      SpeechWindow(samples: 10_000 ..< 18_000, speechConfidence: 0.2),
      SpeechWindow(samples: 14_000 ..< 22_000, speechConfidence: 0.1),
    ]

    let cut = PauseCutPoint.find(in: windows, audio: pcm(samples), audioStart: 6_000)

    #expect(cut == 11_440)
  }

  @Test func ignoresPausesWhoseAudioIsAlreadySent() {
    let audio = pcm([Int16](repeating: 0, count: 8_000))
    let windows = [SpeechWindow(samples: 0 ..< 8_000, speechConfidence: 0.1)]

    #expect(PauseCutPoint.find(in: windows, audio: audio, audioStart: 2_000) == nil)
  }
}
