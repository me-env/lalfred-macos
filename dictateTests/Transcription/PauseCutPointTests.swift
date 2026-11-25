import Foundation
import Testing
@testable import L_Alfred

struct PauseCutPointTests {
  private func pcm(_ samples: [Int16]) -> Data {
    samples.withUnsafeBytes { Data($0) }
  }

  @Test func cutsOnTheQuietestFrameOfThePause() {
    var samples = [Int16](repeating: 500, count: 16_000)
    // The quietest 20 ms frame inside the pause, which starts at 4_000; recording position 11_280.
    for index in 5_280 ..< 5_600 { samples[index] = 1 }
    // A quieter frame outside the pause is not chosen.
    for index in 12_000 ..< 12_320 { samples[index] = 0 }

    let cut = PauseCutPoint.quietestFrameCenter(in: 10_000 ..< 18_000, audio: pcm(samples), audioStart: 6_000)

    #expect(cut == 11_440)
  }

  @Test func meanEnergyIsPerSample() {
    let audio = pcm([Int16](repeating: 10, count: 1_000) + [Int16](repeating: 0, count: 1_000))

    #expect(PauseCutPoint.meanEnergy(of: 500 ..< 1_500, audio: audio, audioStart: 0) == 50)
  }

  @Test func meanEnergyIsUnknownForAudioNoLongerHeld() {
    let audio = pcm([Int16](repeating: 0, count: 8_000))

    #expect(PauseCutPoint.meanEnergy(of: 0 ..< 8_000, audio: audio, audioStart: 2_000) == nil)
    #expect(PauseCutPoint.meanEnergy(of: 4_000 ..< 12_000, audio: audio, audioStart: 2_000) == nil)
  }
}
