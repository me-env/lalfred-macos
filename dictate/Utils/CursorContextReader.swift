import ApplicationServices
import Foundation
import OSLog


private let logger = Logger(subsystem: "fr.lalfred.dictate", category: "CursorContextReader")


protocol CursorContextReading {
  func readContext() -> CursorTextContext?
}

func numberOfCharsForGroup(in element: AXUIElement) -> Int? {
  let subRole = AXAttr.string("AXSubrole", in: element)

  switch subRole {
  case "AXEmptyGroup":
    return 0
  case nil:
    return 0
  default:
    logger.error("Chars count for AXGroup with subrole=\(String(describing: subRole)) unknown")
    return nil
  }
}
  
func finalElementText(in element: AXUIElement) -> String? {
  let role = AXAttr.string("AXRole", in: element)

  switch role {
  case "AXStaticText":
    guard let value = AXAttr.string("AXValue", in: element) else {
      logger.error("No AXValue for AXStaticText")
      return ""
    }
    return value

  case "AXGroup":  /// Never seen a group which contains text as final element
    return ""

  default:
    logger.error("Text extraction for role \(String(describing: role)) : not implemented")
    return ""
  }
}

func finalElementNumberOfChars(in element: AXUIElement) -> Int? {
  let role = AXAttr.string("AXRole", in: element)

  switch role {
  case "AXStaticText":
    guard let value = AXAttr.string("AXValue", in: element) else {
      logger.error("No AXValue for AXStaticText")
      return 0
    }
    return value.count

  case "AXGroup":
    return numberOfCharsForGroup(in: element)

  default:
    let res = AXAttr.int("AXNumberOfCharacters", in: element)
    if res == nil {
      logger.error("role \(String(describing: role)) chars count not found")
    }
    return res
  }
}

func numberOfCharsManual(in element: AXUIElement, depth: Int = 0, isALine: Bool = false) -> Int {
  let children = AXAttr.getChildren(in: element) ?? []

  guard children.count != 0 else {
    guard let charsCount = finalElementNumberOfChars(in: element) else {
      logger.error("Final element has no char count")
      return 0
    }
    return isALine ? charsCount + 1 : charsCount
  }
  let res = children.map { item in
    numberOfCharsManual(in: item, depth: depth + 1, isALine: true)
  }.reduce(0, +)
  
  if depth == 0 { return res - 1 }  /// -1 cause last line does not have next line
  return res
}

struct Line {
  let text: String
  let cursorPos: Int?
  
  init(text: String, cursorPos: Int? = nil) {
    self.text = text
    self.cursorPos = cursorPos
  }
}

func getLines(
  in element: AXUIElement,
  cursorPosToCorrect: inout Int,
  charsCountUntilNow: inout Int,
  depth: Int = 0
) -> [Line] {
  let children = AXAttr.getChildren(in: element)
  
  guard let children, children.count != 0 else {
    guard let text = finalElementText(in: element) else {
      logger.error("Final element has no text")
      return []
    }
    var cursorPos = AXAttr.cursorLocation(in: element)

    let c = cursorPosToCorrect; let d = charsCountUntilNow; logger.info("pos=\(String(describing: cursorPos)) cursorPosToCorrect=\(c) charsCountUntilNow=\(d)")
    if cursorPos == 0 {
      cursorPos = nil
      if charsCountUntilNow == cursorPosToCorrect { cursorPos = 0 }
    }
    charsCountUntilNow += text.count
    let a = cursorPosToCorrect; let b = charsCountUntilNow; logger.info("txt=\(text) cursorPosToCorrect=\(a) charsCountUntilNow=\(b)")
    if !text.isEmpty && charsCountUntilNow <= cursorPosToCorrect {
      cursorPosToCorrect += 1
      let oui = cursorPosToCorrect; logger.info("cursorPosToCorrect \(oui)")
    }
    charsCountUntilNow += 1 /// Adding \n

    return [Line(text: text, cursorPos: cursorPos)]
  }
  let res = children.map { item in getLines(in: item, cursorPosToCorrect: &cursorPosToCorrect, charsCountUntilNow: &charsCountUntilNow, depth: depth + 1) }.flatMap({ $0 })
  return res
}

struct CursorContextReader: CursorContextReading {
  
  private let lookbackLimit = 64
  
  func printTree(from element: AXUIElement, depth: Int = 0) {
    AXAttr.printAttributes(in: element, prefix: String(repeating: " ", count: depth))
    
    let children = AXAttr.getChildren(in: element)
    
    if let children, !children.isEmpty {
      for child in children {
        print("\(String(repeating: " ", count: depth))============ NEXT \(depth) ============")
        printTree(from: child, depth: depth + 1)
      }
    }
  }
  
  func getNativeRawContext(element: AXUIElement, cursorPos: Int) -> RawCursorTextContext? {
    guard let text = AXAttr.string("AXValue", in: element) else {
      logger.error("AX value not set")
      return nil
    }
    return RawCursorTextContext(text: text, cursorPosition: cursorPos)
  }
  
  func getCursorPosFromLines(lines: [Line]) -> Int {
    guard lines.count > 0 else { return 0 }
    let linesBefore = lines.prefix(while: { $0.cursorPos == nil })
    logger.info("linesBefore count \(linesBefore.count)")
    let totalBefore = linesBefore.reduce(into: 0, { $0 += $1.text.count + 1 })
    guard linesBefore.count < lines.count else {
      logger.error("no line contains cursorPos")
      return 0
    }
    let cursorPos = totalBefore + lines[linesBefore.count].cursorPos!
    logger.info("Cursor pos \(cursorPos)")
    return cursorPos
  }
  
  func getRawContextFromAnalysis(in element: AXUIElement, naiveCursorPos: Int) -> RawCursorTextContext? {
    var cursorPosToCorrect: Int = naiveCursorPos
    var charsCountUntilNow: Int = 0
    
    let lines: [Line] = getLines(in: element, cursorPosToCorrect: &cursorPosToCorrect, charsCountUntilNow: &charsCountUntilNow)
    logger.debug("==== LINES ====")
    for line in lines {
      logger.debug("ln=\(line.text) pos=\(String(describing: line.cursorPos))")
    }
    logger.debug("==== LINES END ====")
    let text = lines.map(\.text).joined(separator: "\n")
    let cursorPos = getCursorPosFromLines(lines: lines)
    logger.debug("cursorPos=\(cursorPos)")
    
    let rawContext = RawCursorTextContext(text: text, cursorPosition: cursorPos)
    return rawContext
  }
  
  func printParent(element: AXUIElement) {
    guard let parent = AXAttr.getParent(in: element) else { return }
    print("============ PARENT ============")
    AXAttr.printAttributes(in: parent)
    print("============ ------ ============")
  }
  
  func debugPrint(element: AXUIElement) {
    print("============ SELECTED ============")
    AXAttr.printAttributes(in: element)
    print("============ -------- ============")
    
    print("============ TREE ============")
    printTree(from: element)
    print("============ ---- ============")
  }
  
  func readContext() -> CursorTextContext? {
    guard let element = AXAttr.copyFocusedElement() else {
      logger.info("[CursorContextReader] No focused element")
      return nil
    }
    guard let cursorPos = AXAttr.cursorLocation(in: element) else {
      logger.info("[CursorContextReader] Cursor position not found")
      return nil
    }
    
//    debugPrint(element: element)
    
    let totalElementsStd = finalElementNumberOfChars(in: element) ?? 0
    let totalElementsManual = numberOfCharsManual(in: element)
    let domClassList = AXAttr.stringArray(kAXDOMClassListAttribute, in: element) ?? []
    
    var context: RawCursorTextContext? = nil
    
    logger.debug("totalElementsStd=\(totalElementsStd) totalElementsManual=\(totalElementsManual)")
    
    if domClassList.contains("aislash-editor-input") {
      /**
       Ideas to detect cases like cursor : those with cursor pos = 0 (instead of nil for all cases)
       or we always get data from the DOM. e.g. for outlook we use AXIntersectionWithSelectionRange for cursor pos in a line
       */
      logger.info("getRawContextFromAnalysis")
      context = getRawContextFromAnalysis(in: element, naiveCursorPos: cursorPos)
    } else {
      logger.info("getNativeRawContext")
      context = getNativeRawContext(element: element, cursorPos: cursorPos)
    }
    
    guard let context else {
      logger.error("Failed to resolve Raw context")
      return .empty
    }
    
    context.printContext()
    let cursorContext = context.toCursorTextContext()
    return cursorContext
    
    // TODO: review below starts to see if something interesting is in there
//    TextMarkerSelectionStrategy.run(in: element, lookback: lookbackLimit)
//    CFRangeLineByLineStrategy.run(in: element, cursorPos: cursorPos, lookback: lookbackLimit)
//    TextMarkerLineByIndexStrategy.run(in: element, lookback: lookbackLimit)
//    TextMarkerLineWalkStrategy.run(in: element, lookback: lookbackLimit)
  }
}
