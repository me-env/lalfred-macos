import ApplicationServices
import Foundation
import OSLog


private let logger = Logger(subsystem: "fr.lalfred.dictate", category: "CursorContextReader")


protocol CursorContextReading {
  func readContext() -> CursorTextContext?
}

struct CursorContextReader: CursorContextReading {
  private let lookbackLimit = 64

  func readContext() -> CursorTextContext? {
    guard let element = copyFocusedElement() else { return nil }
    guard let cursorPos = readCursorLocation(in: element) else { return nil }
    logFullReadability(in: element, cursorPos: cursorPos)
    logAllAttributeValues(in: element)
    logAllParameterizedAttributes(in: element, cursorPos: cursorPos)
    guard cursorPos > 0 else {
      return CursorTextContext.empty
    }

    if let prefix = readStringForRange(in: element, cursorPos: cursorPos) {
      return makeContext(prefix: prefix)
    }
    if let prefix = readPrefixFromValue(in: element, cursorPos: cursorPos) {
      return makeContext(prefix: prefix)
    }
    logger.info("[CursorContextReader] Failed to read text around cursor")
    return nil
  }

  private func copyFocusedElement() -> AXUIElement? {
    let systemWide = AXUIElementCreateSystemWide()
    var focusedRef: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(
      systemWide,
      kAXFocusedUIElementAttribute as CFString,
      &focusedRef
    )
    guard err == .success, let ref = focusedRef else {
      logger.info("[CursorContextReader] No focused element (err=\(err.rawValue))")
      return nil
    }
    let element = ref as! AXUIElement
    logFocusedElement(element)
    return element
  }

  private func logFocusedElement(_ element: AXUIElement) {
    var pid: pid_t = 0
    let pidStr: String = AXUIElementGetPid(element, &pid) == .success ? "\(pid)" : "?"

    let role = copyStringAttribute(element, kAXRoleAttribute) ?? "<none>"
    let subrole = copyStringAttribute(element, kAXSubroleAttribute) ?? "<none>"
    let roleDesc = copyStringAttribute(element, kAXRoleDescriptionAttribute) ?? "<none>"
    let title = copyStringAttribute(element, kAXTitleAttribute) ?? "<none>"
    let descr = copyStringAttribute(element, kAXDescriptionAttribute) ?? "<none>"
    let identifier = copyStringAttribute(element, kAXIdentifierAttribute) ?? "<none>"

    logger.info(
      """
      [CursorContextReader] Focused element pid=\(pidStr, privacy: .public) \
      role=\(role, privacy: .public) subrole=\(subrole, privacy: .public) \
      roleDesc=\(roleDesc, privacy: .public) identifier=\(identifier, privacy: .public) \
      title=\(title, privacy: .public) description=\(descr, privacy: .public)
      """
    )

    if let names = copyStringArray(AXUIElementCopyAttributeNames, element) {
      let joined = names.joined(separator: ", ")
      logger.debug("[CursorContextReader] Attributes: \(joined, privacy: .public)")
    }
    if let names = copyStringArray(AXUIElementCopyParameterizedAttributeNames, element) {
      let joined = names.joined(separator: ", ")
      logger.debug("[CursorContextReader] Parameterized attributes: \(joined, privacy: .public)")
    }
    if let names = copyStringArray(AXUIElementCopyActionNames, element) {
      let joined = names.joined(separator: ", ")
      logger.debug("[CursorContextReader] Actions: \(joined, privacy: .public)")
    }
  }

  private func copyStringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success
    else { return nil }
    return ref as? String
  }

  private func copyStringArray(
    _ fn: (AXUIElement, UnsafeMutablePointer<CFArray?>) -> AXError,
    _ element: AXUIElement
  ) -> [String]? {
    var ref: CFArray?
    guard fn(element, &ref) == .success, let array = ref as? [String] else { return nil }
    return array
  }

  private func copyIntAttribute(_ element: AXUIElement, _ attribute: String) -> Int? {
    var ref: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success
    else { return nil }
    return (ref as? NSNumber)?.intValue
  }

  private func copyStringForRange(
    in element: AXUIElement, location: Int, length: Int
  ) -> (string: String?, err: AXError) {
    guard length >= 0 else { return (nil, .failure) }
    if length == 0 { return ("", .success) }
    var range = CFRange(location: location, length: length)
    guard let rangeAXValue = AXValueCreate(.cfRange, &range) else { return (nil, .failure) }

    var ref: CFTypeRef?
    let err = AXUIElementCopyParameterizedAttributeValue(
      element,
      kAXStringForRangeParameterizedAttribute as CFString,
      rangeAXValue,
      &ref
    )
    guard err == .success, let s = ref as? String else { return (nil, err) }
    return (s, .success)
  }

  private func logFullReadability(in element: AXUIElement, cursorPos: Int) {
    let total = copyIntAttribute(element, kAXNumberOfCharactersAttribute)
    let totalStr = total.map { "\($0)" } ?? "?"

    let (prefix, prefixErr) = copyStringForRange(in: element, location: 0, length: cursorPos)
    let prefixDesc = prefix.map { "\($0.utf16.count) chars" }
      ?? "FAILED(err=\(prefixErr.rawValue))"

    let suffixDesc: String
    if let total = total, cursorPos <= total {
      let (suffix, suffixErr) = copyStringForRange(
        in: element, location: cursorPos, length: total - cursorPos
      )
      suffixDesc = suffix.map { "\($0.utf16.count) chars" }
        ?? "FAILED(err=\(suffixErr.rawValue))"
    } else {
      suffixDesc = "SKIPPED(total=\(totalStr))"
    }

    let fullValue = copyStringAttribute(element, kAXValueAttribute)
    let valueDesc = fullValue.map { "\($0.utf16.count) chars" } ?? "FAILED"

    logger.info(
      """
      [CursorContextReader] Read capability \
      cursorPos=\(cursorPos, privacy: .public) \
      AXNumberOfCharacters=\(totalStr, privacy: .public) \
      prefixViaStringForRange=\(prefixDesc, privacy: .public) \
      suffixViaStringForRange=\(suffixDesc, privacy: .public) \
      fullViaAXValue=\(valueDesc, privacy: .public)
      """
    )
  }

  private func logAllAttributeValues(in element: AXUIElement) {
    guard let names = copyStringArray(AXUIElementCopyAttributeNames, element) else { return }
    for name in names.sorted() {
      var ref: CFTypeRef?
      let err = AXUIElementCopyAttributeValue(element, name as CFString, &ref)
      let desc: String
      if err != .success {
        desc = "<err=\(err.rawValue)>"
      } else if let value = ref {
        desc = describeAXValue(value)
      } else {
        desc = "<nil>"
      }
      logger.debug(
        "[CursorContextReader] attr \(name, privacy: .public) = \(desc, privacy: .public)"
      )
    }
  }

  private func logAllParameterizedAttributes(in element: AXUIElement, cursorPos: Int) {
    guard let names = copyStringArray(AXUIElementCopyParameterizedAttributeNames, element)
    else { return }

    for name in names.sorted() {
      guard let (param, paramDesc) = probeParameter(forName: name, cursorPos: cursorPos) else {
        logger.debug(
          "[CursorContextReader] param \(name, privacy: .public) skipped (no known parameter shape)"
        )
        continue
      }
      var ref: CFTypeRef?
      let err = AXUIElementCopyParameterizedAttributeValue(
        element, name as CFString, param, &ref
      )
      let desc: String
      if err != .success {
        desc = "<err=\(err.rawValue)>"
      } else if let value = ref {
        desc = describeAXValue(value)
      } else {
        desc = "<nil>"
      }
      logger.debug(
        """
        [CursorContextReader] param \(name, privacy: .public)\
        (\(paramDesc, privacy: .public)) = \(desc, privacy: .public)
        """
      )
    }
  }

  private func probeParameter(forName name: String, cursorPos: Int)
    -> (param: CFTypeRef, description: String)?
  {
    if name.contains("TextMarker") { return nil }
    if name.hasSuffix("ForRange") {
      let length = min(max(cursorPos, 0), 8)
      var range = CFRange(location: max(0, cursorPos - length), length: length)
      guard let value = AXValueCreate(.cfRange, &range) else { return nil }
      return (value, "CFRange(\(range.location),\(range.length))")
    }
    if name.hasSuffix("ForIndex") {
      let n = NSNumber(value: cursorPos)
      return (n as CFTypeRef, "Index=\(cursorPos)")
    }
    if name.hasSuffix("ForLine") {
      let n = NSNumber(value: 0)
      return (n as CFTypeRef, "Line=0")
    }
    if name.hasSuffix("ForPosition") {
      var p = CGPoint.zero
      guard let value = AXValueCreate(.cgPoint, &p) else { return nil }
      return (value, "CGPoint(0,0)")
    }
    return nil
  }

  private func describeAXValue(_ ref: CFTypeRef) -> String {
    let id = CFGetTypeID(ref)

    if id == AXValueGetTypeID() {
      let axv = ref as! AXValue
      switch AXValueGetType(axv) {
      case .cfRange:
        var r = CFRange()
        AXValueGetValue(axv, .cfRange, &r)
        return "CFRange(loc=\(r.location), len=\(r.length))"
      case .cgPoint:
        var p = CGPoint.zero
        AXValueGetValue(axv, .cgPoint, &p)
        return "CGPoint(\(p.x), \(p.y))"
      case .cgSize:
        var s = CGSize.zero
        AXValueGetValue(axv, .cgSize, &s)
        return "CGSize(\(s.width), \(s.height))"
      case .cgRect:
        var rect = CGRect.zero
        AXValueGetValue(axv, .cgRect, &rect)
        return "CGRect(\(rect.origin.x), \(rect.origin.y), \(rect.size.width), \(rect.size.height))"
      case .axError:
        var e = AXError.success
        AXValueGetValue(axv, .axError, &e)
        return "AXError(\(e.rawValue))"
      case .illegal:
        return "<AXValue illegal>"
      @unknown default:
        return "<AXValue unknown>"
      }
    }

    if id == AXUIElementGetTypeID() {
      let el = ref as! AXUIElement
      let role = copyStringAttribute(el, kAXRoleAttribute) ?? "?"
      return "<AXUIElement role=\(role)>"
    }

    if id == CFBooleanGetTypeID() {
      return CFBooleanGetValue((ref as! CFBoolean)) ? "true" : "false"
    }

    if let s = ref as? String { return truncated(s) }
    if let u = ref as? URL { return u.absoluteString }
    if let n = ref as? NSNumber { return "\(n)" }
    if let arr = ref as? [Any] { return "[count=\(arr.count)]" }
    if let attr = ref as? NSAttributedString {
      return "AttributedString(" + truncated(attr.string) + ")"
    }

    return "<\(CFCopyTypeIDDescription(id) as String)>"
  }

  private func truncated(_ s: String, limit: Int = 120) -> String {
    let escaped = s.replacingOccurrences(of: "\n", with: "\\n")
    if escaped.utf16.count <= limit { return "\"\(escaped)\"" }
    let head = String(escaped.prefix(limit))
    return "\"\(head)…\" (\(s.utf16.count) total)"
  }

  private func readCursorLocation(in element: AXUIElement) -> Int? {
    var rangeRef: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(
      element,
      kAXSelectedTextRangeAttribute as CFString,
      &rangeRef
    )
    guard err == .success, let ref = rangeRef else {
      logger.info("[CursorContextReader] No selected text range (err=\(err.rawValue))")
      return nil
    }
    let axValue = ref as! AXValue
    var range = CFRange()
    guard AXValueGetType(axValue) == .cfRange,
          AXValueGetValue(axValue, .cfRange, &range) else {
      logger.info("[CursorContextReader] Range value is not a CFRange")
      return nil
    }
    return range.location
  }

  private func readStringForRange(in element: AXUIElement, cursorPos: Int) -> String? {
    let lookback = min(cursorPos, lookbackLimit)
    var prefixRange = CFRange(location: cursorPos - lookback, length: lookback)
    guard let rangeAXValue = AXValueCreate(.cfRange, &prefixRange) else { return nil }

    var prefixRef: CFTypeRef?
    let err = AXUIElementCopyParameterizedAttributeValue(
      element,
      kAXStringForRangeParameterizedAttribute as CFString,
      rangeAXValue,
      &prefixRef
    )
    guard err == .success, let prefix = prefixRef as? String else {
      logger.debug("[CursorContextReader] StringForRange not supported (err=\(err.rawValue))")
      return nil
    }
    return prefix
  }

  private func readPrefixFromValue(in element: AXUIElement, cursorPos: Int) -> String? {
    var valueRef: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(
      element,
      kAXValueAttribute as CFString,
      &valueRef
    )
    guard err == .success, let value = valueRef as? String else {
      logger.debug("[CursorContextReader] Value attribute unavailable (err=\(err.rawValue))")
      return nil
    }
    let utf16 = value.utf16
    guard cursorPos <= utf16.count,
          let utf16Index = utf16.index(
            utf16.startIndex,
            offsetBy: cursorPos,
            limitedBy: utf16.endIndex
          ),
          let stringIndex = String.Index(utf16Index, within: value) else {
      return nil
    }
    let lookback = min(cursorPos, lookbackLimit)
    let utf16Start = utf16.index(utf16Index, offsetBy: -lookback, limitedBy: utf16.startIndex)
      ?? utf16.startIndex
    guard let startIndex = String.Index(utf16Start, within: value) else { return nil }
    return String(value[startIndex..<stringIndex])
  }

  private func makeContext(prefix: String) -> CursorTextContext {
    var previousNonWhitespaceCharacter: Character? = nil
    var hasLineBreakBeforeCursor = false

    for ch in prefix.reversed() {
      if ch.isNewline {
        hasLineBreakBeforeCursor = true
      } else if !ch.isWhitespace {
        previousNonWhitespaceCharacter = ch
        break
      }
    }

    return CursorTextContext(
      previousCharacter: prefix.last,
      previousNonWhitespaceCharacter: previousNonWhitespaceCharacter,
      hasLineBreakBeforeCursor: hasLineBreakBeforeCursor
    )
  }
}
