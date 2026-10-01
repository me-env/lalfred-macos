import Foundation

struct DictationSessionStateMachine {
  enum State {
    case idle
    case listening
    case processing
  }
  
  private(set) var state: State = .idle
  
  var isListening: Bool {
    state == .listening
  }
  
  mutating func transitionToListening() -> Bool {
    guard state == .idle else { return false }
    state = .listening
    return true
  }
  
  mutating func transitionToProcessing() -> Bool {
    guard state == .listening else { return false }
    state = .processing
    return true
  }
  
  /// Retrying a previous recording goes straight from idle to processing.
  mutating func transitionToRetryProcessing() -> Bool {
    guard state == .idle else { return false }
    state = .processing
    return true
  }
  
  mutating func transitionToIdle() {
    state = .idle
  }
  
}
