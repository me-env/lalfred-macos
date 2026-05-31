import ApplicationServices
import Foundation

private let defaultExcludedDebugAttributeNames: Set<String> = [
//  "AXContentSize",
  "AXPath",
  "AXCustomContent",
  "AXCustomRotors",
  "AXFrame",
  "AXRelativeFrame",
  "AXPosition",
  "AXRoleDescription",
  "AXSelectedTextRanges",
  "AXSharedCharacterRange",
  "AXSharedTextUIElements",
  "AXSize",
  "_AXPrimaryScreenHeight",
//  "AXTextualContent",
  "AXTopLevelUIElement",
  "AXVerticalScrollBar",
  "AXWindow",
  "AXEndTextMarker",
  "AXHighestEditableAncestor",
  "AXInsertionPointLineNumber",
  "AXLanguage",
  "AXSelectedTextMarkerRange",
  "AXStartTextMarker",
  "ChromeAXNodeId",
  "AXFocusableAncestor",
  "AXEnabled",
  "AXEditableAncestor"
]

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

  // MARK: - Debugging
  
  static func getChildren(in element: AXUIElement) -> [AXUIElement]? {
      AXAttr.UIElementArray(kAXChildrenAttribute, in: element)
  }

  static func getParent(in element: AXUIElement) -> AXUIElement? {
      AXAttr.UIElement(kAXParentAttribute, in: element)
  }

  static func printAttributes(
    in element: AXUIElement,
    attributes: Array<String>? = nil,
    excludedAttributes: Set<String> = defaultExcludedDebugAttributeNames,
    prefix: String = "",
    includeErrors: Bool = false,
    includeEmpty: Bool = false
  ) {
    guard let names = stringArray(AXUIElementCopyAttributeNames, in: element) else {
      print("\(prefix)AX attributes: unable to read attribute names")
      return
    }

    for name in names.sorted() {
      if let attributes,
         !attributes.contains(name) {
        continue
      }

      if excludedAttributes.contains(name) {
        continue
      }
      
      var ref: CFTypeRef?
      let error = AXUIElementCopyAttributeValue(element, name as CFString, &ref)
      
      guard error == .success else {
        if includeErrors {
          print("\(prefix)\(name): <unavailable: \(error)>")
        }
        continue
      }
      guard includeEmpty || hasPrintableValue(ref) else {
        continue
      }
      print("\(prefix)\(name): \(debugDescription(for: ref))")
    }
    let cursorPos = AXAttr.cursorLocation(in: element)
    print("\(prefix)cursor pos: \(String(describing: cursorPos))")
  }

  private static func hasPrintableValue(_ ref: CFTypeRef?) -> Bool {
    guard let ref else { return false }

    if CFGetTypeID(ref) == AXValueGetTypeID() {
      return hasPrintableValue(ref as! AXValue)
    }

    if let string = ref as? String {
      return !string.isEmpty
    }

    if let array = ref as? [Any] {
      return !array.isEmpty
    }

    if let dictionary = ref as? [AnyHashable: Any] {
      return !dictionary.isEmpty
    }

    if let number = ref as? NSNumber {
      return number != 0
    }

    if let data = ref as? Data {
      return !data.isEmpty
    }

    if let attributedString = ref as? NSAttributedString {
      return attributedString.length > 0
    }

    return true
  }

  private static func hasPrintableValue(_ value: AXValue) -> Bool {
    switch AXValueGetType(value) {
    case .cfRange:
      var range = CFRange()
      guard AXValueGetValue(value, .cfRange, &range) else { return true }
      return true
    case .cgPoint:
      var point = CGPoint.zero
      guard AXValueGetValue(value, .cgPoint, &point) else { return true }
      return point != .zero
    case .cgSize:
      var size = CGSize.zero
      guard AXValueGetValue(value, .cgSize, &size) else { return true }
      return size != .zero
    case .cgRect:
      var rect = CGRect.zero
      guard AXValueGetValue(value, .cgRect, &rect) else { return true }
      return rect != .zero
    case .axError:
      var error = AXError.success
      guard AXValueGetValue(value, .axError, &error) else { return true }
      return error != .success
    case .illegal:
      return false
    @unknown default:
      return true
    }
  }

  private static func debugDescription(for ref: CFTypeRef?) -> String {
    guard let ref else { return "nil" }

    if CFGetTypeID(ref) == AXValueGetTypeID() {
      return debugDescription(for: ref as! AXValue)
    }

    if let array = ref as? [Any] {
      return "[" + array.map { debugDescription(for: $0 as CFTypeRef) }.joined(separator: ", ") + "]"
    }

    if let dictionary = ref as? [AnyHashable: Any] {
      let pairs = dictionary.map { key, value in
        "\(key): \(debugDescription(for: value as CFTypeRef))"
      }
      return "[" + pairs.sorted().joined(separator: ", ") + "]"
    }

    return String(describing: ref)
  }

  private static func debugDescription(for value: AXValue) -> String {
    switch AXValueGetType(value) {
    case .cfRange:
      var range = CFRange()
      guard AXValueGetValue(value, .cfRange, &range) else { return "<AXValue cfRange>" }
      return "CFRange(location: \(range.location), length: \(range.length))"
    case .cgPoint:
      var point = CGPoint.zero
      guard AXValueGetValue(value, .cgPoint, &point) else { return "<AXValue cgPoint>" }
      return "CGPoint(x: \(point.x), y: \(point.y))"
    case .cgSize:
      var size = CGSize.zero
      guard AXValueGetValue(value, .cgSize, &size) else { return "<AXValue cgSize>" }
      return "CGSize(width: \(size.width), height: \(size.height))"
    case .cgRect:
      var rect = CGRect.zero
      guard AXValueGetValue(value, .cgRect, &rect) else { return "<AXValue cgRect>" }
      return "CGRect(x: \(rect.origin.x), y: \(rect.origin.y), width: \(rect.width), height: \(rect.height))"
    case .axError:
      var error = AXError.success
      guard AXValueGetValue(value, .axError, &error) else { return "<AXValue axError>" }
      return "AXError(\(error))"
    case .illegal:
      return "<AXValue illegal>"
    @unknown default:
      return "<AXValue unknown>"
    }
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
  
  static func stringArray(_ name: String, in element: AXUIElement) -> [String]? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &ref) == .success
    else { return nil }
    return (ref as? [String])
  }

  static func UIElement(_ name: String, in element: AXUIElement) -> AXUIElement? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &ref) == .success,
          let ref else { return nil }
    
    let axElement = ref as! AXUIElement
    return axElement
  }
  
  static func UIElementArray(_ name: String, in element: AXUIElement) -> Array<AXUIElement>? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &ref) == .success
    else { return nil }
    return ref as? [AXUIElement]
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
