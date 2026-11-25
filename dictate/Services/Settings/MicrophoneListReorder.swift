import CoreGraphics

/// Where a microphone dragged in the priority list goes, from the pointer and the rows' frames.
nonisolated enum MicrophoneListReorder {
  /// The index the dragged microphone moves to, or nil to leave it in place. It moves once the pointer
  /// passes the middle of another row, so rows of different heights do not swap back and forth.
  static func destinationIndex(
    dragging draggedUID: String,
    pointerY: CGFloat,
    order: [String],
    frames: [String: CGRect]
  ) -> Int? {
    guard let draggedIndex = order.firstIndex(of: draggedUID),
          let targetIndex = rowIndex(at: pointerY, order: order, frames: frames),
          targetIndex != draggedIndex,
          let target = frames[order[targetIndex]] else {
      return nil
    }
    let hasPassedMiddle = targetIndex > draggedIndex ? pointerY > target.midY : pointerY < target.midY
    return hasPassedMiddle ? targetIndex : nil
  }

  private static func rowIndex(at pointerY: CGFloat, order: [String], frames: [String: CGRect]) -> Int? {
    order.firstIndex { uid in
      guard let frame = frames[uid] else { return false }
      return (frame.minY...frame.maxY).contains(pointerY)
    }
  }
}
