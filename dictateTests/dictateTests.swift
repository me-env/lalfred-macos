//
//  dictateTests.swift
//  dictateTests
//
//  Created by Cyprien Ricque on 4/26/26.
//

import Testing
@testable import dictate

struct dictateTests {
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

    @Test func stateMachineCanShowModeSwitcherOnlyWhileListening() {
        var machine = DictationSessionStateMachine()
        #expect(machine.canShowModeSwitcher(isModeSwitcherVisible: false) == false)
        _ = machine.transitionToListening()
        #expect(machine.canShowModeSwitcher(isModeSwitcherVisible: false))
        #expect(machine.canShowModeSwitcher(isModeSwitcherVisible: true) == false)
    }
}
