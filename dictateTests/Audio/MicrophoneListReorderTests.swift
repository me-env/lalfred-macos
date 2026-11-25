import CoreGraphics
import Testing
@testable import L_Alfred

struct MicrophoneListReorderTests {
  private let order = ["usb", "airpods", "internal"]
  /// A short row, a tall row (with a caption) and a short row, 6 points apart.
  private let frames: [String: CGRect] = [
    "usb": CGRect(x: 0, y: 0, width: 300, height: 30),
    "airpods": CGRect(x: 0, y: 36, width: 300, height: 44),
    "internal": CGRect(x: 0, y: 86, width: 300, height: 30),
  ]

  private func destination(dragging uid: String, at pointerY: CGFloat) -> Int? {
    MicrophoneListReorder.destinationIndex(dragging: uid, pointerY: pointerY, order: order, frames: frames)
  }

  @Test func movesDownOncePastTheMiddleOfTheRowBelow() {
    #expect(destination(dragging: "usb", at: 50) == nil)
    #expect(destination(dragging: "usb", at: 70) == 1)
    #expect(destination(dragging: "usb", at: 110) == 2)
  }

  @Test func movesUpOncePastTheMiddleOfTheRowAbove() {
    #expect(destination(dragging: "internal", at: 70) == nil)
    #expect(destination(dragging: "internal", at: 45) == 1)
    #expect(destination(dragging: "internal", at: 5) == 0)
  }

  @Test func staysPutOverItselfBetweenRowsOrForAnUnknownMicrophone() {
    #expect(destination(dragging: "airpods", at: 60) == nil)
    #expect(destination(dragging: "usb", at: 33) == nil)
    #expect(destination(dragging: "unknown", at: 110) == nil)
  }

  @Test func doesNotSwapBackAfterMovingPastATallerRow() {
    let swapped = ["airpods", "usb", "internal"]
    let swappedFrames: [String: CGRect] = [
      "airpods": CGRect(x: 0, y: 0, width: 300, height: 44),
      "usb": CGRect(x: 0, y: 50, width: 300, height: 30),
      "internal": CGRect(x: 0, y: 86, width: 300, height: 30),
    ]
    let destination = MicrophoneListReorder.destinationIndex(
      dragging: "usb", pointerY: 70, order: swapped, frames: swappedFrames
    )
    #expect(destination == nil)
  }
}
