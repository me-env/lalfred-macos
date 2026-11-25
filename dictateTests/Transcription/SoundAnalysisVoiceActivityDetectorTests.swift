import Foundation
import Testing
@testable import L_Alfred

struct SoundAnalysisVoiceActivityDetectorTests {
  @Test func silenceIsNotSpeechAndWindowsUseRecordingPositions() throws {
    let detector = try SoundAnalysisVoiceActivityDetector()
    let start = 20 * TranscriptionAudio.sampleRate
    let chunk = Data(count: 3_200)

    var windows: [SpeechWindow] = []
    for index in 0 ..< 15 {
      windows += detector.analyze(chunk, startingAt: start + index * 1_600)
    }

    #expect(windows.first?.samples == start ..< start + 8_000)
    #expect(windows.count >= 4)
    #expect(windows.allSatisfy { $0.speechConfidence < PauseTracker.silenceConfidence })
  }
}
