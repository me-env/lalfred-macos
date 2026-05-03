import Testing
@testable import L_Alfred

struct lalfredTests {
    @Test func stateMachineTransitionsFromIdleToListening() {
        var machine = DictationSessionStateMachine()
        #expect(machine.transitionToListening())
        #expect(machine.state == .listening)
    }

    @Test func stateMachineTransitionsFromListeningToProcessing() {
        var machine = DictationSessionStateMachine()
        _ = machine.transitionToListening()
        #expect(machine.transitionToProcessing())
        #expect(machine.state == .processing)
    }

    @Test func stateMachineRejectsInvalidTransitionToProcessingFromIdle() {
        var machine = DictationSessionStateMachine()
        #expect(machine.transitionToProcessing() == false)
        #expect(machine.state == .idle)
    }

    @Test func stateMachineCanShowModeSwitcherWhileIdleOrListening() {
        var machine = DictationSessionStateMachine()
        #expect(machine.canShowModeSwitcher(isCommandVisible: false))
        _ = machine.transitionToListening()
        #expect(machine.canShowModeSwitcher(isCommandVisible: false))
        #expect(machine.canShowModeSwitcher(isCommandVisible: true) == false)
        _ = machine.transitionToProcessing()
        #expect(machine.canShowModeSwitcher(isCommandVisible: false) == false)
    }
}
