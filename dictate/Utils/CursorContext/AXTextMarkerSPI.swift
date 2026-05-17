import ApplicationServices
import Foundation


// MARK: - Private HIServices AXTextMarker SPI bindings
//
// `AXTextMarker` / `AXTextMarkerRange` are SPI in HIServices but stable since macOS 10.4 and
// relied on by VoiceOver. They're required to read text from Chromium / WebKit-based apps
// (VS Code, Chrome, Slack, Discord, Notion, Safari content, …) where the public CFRange-based
// `kAXStringForRangeParameterizedAttribute` / `kAXValueAttribute` may strip line breaks or
// concatenate per-line `<div>` nodes without `\n`.

@_silgen_name("AXTextMarkerRangeCreate")
private func _AXTextMarkerRangeCreate(
  _ allocator: CFAllocator?,
  _ startMarker: AnyObject,
  _ endMarker: AnyObject
) -> Unmanaged<AnyObject>?

@_silgen_name("AXTextMarkerRangeCopyStartMarker")
private func _AXTextMarkerRangeCopyStartMarker(
  _ range: AnyObject
) -> Unmanaged<AnyObject>?

@_silgen_name("AXTextMarkerRangeCopyEndMarker")
private func _AXTextMarkerRangeCopyEndMarker(
  _ range: AnyObject
) -> Unmanaged<AnyObject>?


/// Swift-friendly wrapper around the AXTextMarker family.
///
/// All `AnyObject` returns are CF marker / marker-range objects; their identity is opaque.
/// Methods that return `nil` mean either the attribute is unsupported on `element`, the
/// underlying call failed, or the returned value wasn't of the expected shape.
enum AXMarker {

  // MARK: - Range construction / decomposition

  static func createRange(from start: AnyObject, to end: AnyObject) -> AnyObject? {
    _AXTextMarkerRangeCreate(kCFAllocatorDefault, start, end)?.takeRetainedValue()
  }

  static func startMarker(of range: AnyObject) -> AnyObject? {
    _AXTextMarkerRangeCopyStartMarker(range)?.takeRetainedValue()
  }

  static func endMarker(of range: AnyObject) -> AnyObject? {
    _AXTextMarkerRangeCopyEndMarker(range)?.takeRetainedValue()
  }

  // MARK: - Per-element marker queries

  /// `AXStartTextMarker` — the first valid marker in the element (or its document).
  static func documentStart(in element: AXUIElement) -> AnyObject? {
    copyAttribute(element, "AXStartTextMarker")
  }

  /// `AXEndTextMarker` — the last valid marker in the element (or its document).
  static func documentEnd(in element: AXUIElement) -> AnyObject? {
    copyAttribute(element, "AXEndTextMarker")
  }

  /// Start marker of `AXSelectedTextMarkerRange` (the cursor / start of any selection).
  static func cursor(in element: AXUIElement) -> AnyObject? {
    guard let selRange = copyAttribute(element, "AXSelectedTextMarkerRange") else { return nil }
    return startMarker(of: selRange)
  }

  /// `AXTextMarkerForIndex(0)` — the marker at character offset 0 of the element.
  static func elementStart(in element: AXUIElement) -> AnyObject? {
    copyParameterized(
      element, "AXTextMarkerForIndex", parameter: NSNumber(value: 0) as CFTypeRef
    )
  }

  // MARK: - Line APIs

  /// `AXTextMarkerRangeForLine(N)` — given a line index, returns the marker range.
  static func lineRange(forLine index: Int, in element: AXUIElement) -> AnyObject? {
    copyParameterized(
      element,
      "AXTextMarkerRangeForLine",
      parameter: NSNumber(value: index) as CFTypeRef
    )
  }

  /// `AXLineForTextMarker(marker)` — given a marker, returns its line index.
  static func lineIndex(of marker: AnyObject, in element: AXUIElement) -> Int? {
    let ref = copyParameterized(
      element, "AXLineForTextMarker", parameter: marker as CFTypeRef
    )
    return (ref as? NSNumber)?.intValue
  }

  /// `AXLineTextMarkerRangeForTextMarker(marker)` — the range covering the line that
  /// contains the marker.
  static func lineRange(for marker: AnyObject, in element: AXUIElement) -> AnyObject? {
    copyParameterized(
      element,
      "AXLineTextMarkerRangeForTextMarker",
      parameter: marker as CFTypeRef
    )
  }

  /// `AXPreviousLineStartTextMarkerForTextMarker(marker)` — the start marker of the
  /// previous line. Returns `nil` (or the same marker, depending on impl) when at start.
  static func previousLineStart(
    for marker: AnyObject, in element: AXUIElement
  ) -> AnyObject? {
    copyParameterized(
      element,
      "AXPreviousLineStartTextMarkerForTextMarker",
      parameter: marker as CFTypeRef
    )
  }

  /// `AXNextLineEndTextMarkerForTextMarker(marker)` — the end marker of the next line.
  static func nextLineEnd(for marker: AnyObject, in element: AXUIElement) -> AnyObject? {
    copyParameterized(
      element,
      "AXNextLineEndTextMarkerForTextMarker",
      parameter: marker as CFTypeRef
    )
  }

  // MARK: - String reading

  /// `AXStringForTextMarkerRange(range)` — text content of a marker range.
  static func string(forRange range: AnyObject, in element: AXUIElement) -> String? {
    let ref = copyParameterized(
      element, "AXStringForTextMarkerRange", parameter: range as CFTypeRef
    )
    return ref as? String
  }

  // MARK: - Internal helpers

  private static func copyAttribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &ref) == .success,
          let r = ref else { return nil }
    return r as AnyObject
  }

  private static func copyParameterized(
    _ element: AXUIElement, _ name: String, parameter: CFTypeRef
  ) -> AnyObject? {
    var ref: CFTypeRef?
    guard AXUIElementCopyParameterizedAttributeValue(
      element, name as CFString, parameter, &ref
    ) == .success, let r = ref else { return nil }
    return r as AnyObject
  }
}
