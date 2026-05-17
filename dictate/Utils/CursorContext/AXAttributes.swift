import ApplicationServices
import Foundation


/// Thin readers around the public `AXUIElement*` C API. All functions return `nil` when
/// the requested attribute is unavailable or the value isn't of the expected shape.
enum AXAttr {

  // MARK: - System / element handles

  static func copyFocusedElement() -> AXUIElement? {
    let systemWide = AXUIElementCreateSystemWide()
    var focusedRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(
      systemWide,
      kAXFocusedUIElementAttribute as CFString,
      &focusedRef
    ) == .success, let ref = focusedRef else { return nil }
    return (ref as! AXUIElement)
  }

  // MARK: - Plain attributes (kAX*)

  static func string(_ name: String, in element: AXUIElement) -> String? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &ref) == .success
    else { return nil }
    return ref as? String
  }

  static func int(_ name: String, in element: AXUIElement) -> Int? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &ref) == .success
    else { return nil }
    return (ref as? NSNumber)?.intValue
  }

  static func stringArray(
    _ fn: (AXUIElement, UnsafeMutablePointer<CFArray?>) -> AXError,
    in element: AXUIElement
  ) -> [String]? {
    var ref: CFArray?
    guard fn(element, &ref) == .success, let array = ref as? [String] else { return nil }
    return array
  }

  static func attributeNames(in element: AXUIElement) -> Set<String> {
    Set(stringArray(AXUIElementCopyAttributeNames, in: element) ?? [])
  }

  static func parameterizedAttributeNames(in element: AXUIElement) -> Set<String> {
    Set(stringArray(AXUIElementCopyParameterizedAttributeNames, in: element) ?? [])
  }

  // MARK: - Selection / cursor in CFRange space

  static func selectedRange(in element: AXUIElement) -> CFRange? {
    var rangeRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(
      element,
      kAXSelectedTextRangeAttribute as CFString,
      &rangeRef
    ) == .success, let ref = rangeRef else { return nil }
    let axValue = ref as! AXValue
    var range = CFRange()
    guard AXValueGetType(axValue) == .cfRange,
          AXValueGetValue(axValue, .cfRange, &range) else { return nil }
    return range
  }

  static func cursorLocation(in element: AXUIElement) -> Int? {
    selectedRange(in: element)?.location
  }

  // MARK: - Parameterized attributes (CFRange-based text APIs)

  /// `kAXStringForRangeParameterizedAttribute`.
  static func string(forRange range: CFRange, in element: AXUIElement) -> String? {
    var r = range
    guard let rangeAXValue = AXValueCreate(.cfRange, &r) else { return nil }
    var ref: CFTypeRef?
    guard AXUIElementCopyParameterizedAttributeValue(
      element,
      kAXStringForRangeParameterizedAttribute as CFString,
      rangeAXValue,
      &ref
    ) == .success else { return nil }
    return ref as? String
  }

  /// `AXRangeForLine` — takes a 0-based line index, returns the line's character range.
  static func cfRange(forLine line: Int, in element: AXUIElement) -> CFRange? {
    var ref: CFTypeRef?
    guard AXUIElementCopyParameterizedAttributeValue(
      element,
      "AXRangeForLine" as CFString,
      NSNumber(value: line) as CFTypeRef,
      &ref
    ) == .success, let v = ref else { return nil }
    let axValue = v as! AXValue
    var range = CFRange()
    guard AXValueGetType(axValue) == .cfRange,
          AXValueGetValue(axValue, .cfRange, &range) else { return nil }
    return range
  }

  /// `AXLineForIndex` — takes a character index, returns its 0-based line number.
  static func line(forIndex index: Int, in element: AXUIElement) -> Int? {
    var ref: CFTypeRef?
    guard AXUIElementCopyParameterizedAttributeValue(
      element,
      "AXLineForIndex" as CFString,
      NSNumber(value: index) as CFTypeRef,
      &ref
    ) == .success else { return nil }
    return (ref as? NSNumber)?.intValue
  }
}
