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

    mutating func transitionToIdle() {
        state = .idle
    }

    func canShowModeSwitcher(isModeSwitcherVisible: Bool) -> Bool {
        state != .processing && !isModeSwitcherVisible
    }
}
