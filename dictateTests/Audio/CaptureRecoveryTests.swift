import Foundation
import Testing
@testable import L_Alfred

struct CaptureDisruptionTests {
  private typealias Devices = AudioTestDevices

  @Test func defaultInputChangeAloneIsNoDisruption() {
    #expect(CaptureDisruption.detect(activeUID: "usb", in: [Devices.usbMic, Devices.airPods], formatMatches: true) == nil)
  }

  @Test func missingMicrophoneIsLost() {
    #expect(CaptureDisruption.detect(activeUID: "usb", in: [Devices.internalMic], formatMatches: true) == .deviceLost)
  }

  @Test func deadMicrophoneIsLost() {
    #expect(CaptureDisruption.detect(activeUID: "usb", in: [Devices.dead(Devices.usbMic)], formatMatches: true) == .deviceLost)
  }

  @Test func formatMismatchIsAFormatChange() {
    #expect(CaptureDisruption.detect(activeUID: "airpods", in: [Devices.airPods], formatMatches: false) == .formatChanged)
  }
}

struct CaptureRecoveryBudgetTests {
  private typealias Devices = AudioTestDevices

  /// Selects the first of `devices` not excluded.
  private func selector(_ devices: [InputDevice]) -> (Set<String>) -> InputDevice? {
    { excludedUIDs in devices.first { !excludedUIDs.contains($0.uid) } }
  }

  @Test func formatChangeRebuildsOnTheSameMicrophone() {
    var budget = CaptureRecoveryBudget()
    #expect(budget.nextMicrophone(after: .formatChanged, on: Devices.airPods, select: selector([Devices.internalMic])) == Devices.airPods)
  }

  @Test func failingMicrophoneGetsOneMoreTryThenIsExcluded() {
    var budget = CaptureRecoveryBudget()
    let select = selector([Devices.usbMic, Devices.internalMic])
    #expect(budget.nextMicrophone(after: .stalled, on: Devices.usbMic, select: select) == Devices.usbMic)
    #expect(budget.nextMicrophone(after: .startTimedOut, on: Devices.usbMic, select: select) == Devices.internalMic)
  }

  @Test func lostMicrophoneIsExcludedRightAway() {
    var budget = CaptureRecoveryBudget()
    #expect(budget.nextMicrophone(after: .deviceLost, on: Devices.usbMic, select: selector([Devices.usbMic, Devices.internalMic])) == Devices.internalMic)
    #expect(budget.excludedUIDs == ["usb"])
  }

  @Test func givesUpWithoutAnotherMicrophone() {
    var budget = CaptureRecoveryBudget()
    #expect(budget.nextMicrophone(after: .deviceLost, on: Devices.usbMic, select: selector([Devices.usbMic])) == nil)
  }

  @Test func givesUpAfterTooManyRebuilds() {
    var budget = CaptureRecoveryBudget()
    let select = selector([Devices.airPods])
    for _ in 0..<CaptureRecoveryBudget.maxRebuilds {
      #expect(budget.nextMicrophone(after: .formatChanged, on: Devices.airPods, select: select) == Devices.airPods)
    }
    #expect(budget.nextMicrophone(after: .formatChanged, on: Devices.airPods, select: select) == nil)
  }
}

struct CaptureWatchdogTests {
  private let start: Double = 100

  private func verdict(_ activity: CaptureActivity, after seconds: Double, isInternalMic: Bool = true) -> CaptureDisruption? {
    CaptureWatchdog.verdict(for: activity, at: start + seconds, isInternalMic: isInternalMic)
  }

  @Test func noCallbackAfterStartTimesOut() {
    let activity = CaptureActivity(startTime: start)
    #expect(verdict(activity, after: 2.9) == nil)
    #expect(verdict(activity, after: 3) == .startTimedOut)
  }

  @Test func callbacksStoppingIsAStall() {
    let activity = CaptureActivity(startTime: start, lastCallbackTime: start + 1, hasDeliveredSound: true)
    #expect(verdict(activity, after: 2.9) == nil)
    #expect(verdict(activity, after: 3) == .stalled)
  }

  @Test func internalMicTurningToZerosIsSilent() {
    let activity = CaptureActivity(startTime: start, lastCallbackTime: start + 5, zeroRunStartTime: start + 2, hasDeliveredSound: true)
    #expect(verdict(activity, after: 4.9) == nil)
    #expect(verdict(activity, after: 5) == .silent)
  }

  @Test func zerosAreFineBeforeSoundOrFromAHeadset() {
    let beforeSound = CaptureActivity(startTime: start, lastCallbackTime: start + 5, zeroRunStartTime: start)
    #expect(verdict(beforeSound, after: 5) == nil)
    let headset = CaptureActivity(startTime: start, lastCallbackTime: start + 5, zeroRunStartTime: start + 1, hasDeliveredSound: true)
    #expect(verdict(headset, after: 5, isInternalMic: false) == nil)
  }
}

struct RecordedAudioTests {
  @Test func emptyAndZeroAudioIsSilent() {
    #expect(RecordedAudio.isDigitallySilent(Data()))
    #expect(RecordedAudio.isDigitallySilent(Data(count: 3_200)))
  }

  @Test func oneNonZeroSampleIsNotSilent() {
    var audio = Data(count: 3_200)
    audio[1_001] = 1
    #expect(!RecordedAudio.isDigitallySilent(audio))
  }
}
