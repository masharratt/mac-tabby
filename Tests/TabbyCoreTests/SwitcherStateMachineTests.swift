import Testing
@testable import TabbyCore

@Suite struct SwitcherStateMachineTests {
    func make(delay: Double = 0.1) -> SwitcherStateMachine {
        SwitcherStateMachine(showDelay: delay)
    }

    @Test func startsIdleAndIgnoresStrayEvents() {
        var m = make()
        #expect(m.state == .idle)
        for event: SwitcherEvent in [.optionReleased, .escape, .returnKey, .arrow(.next), .otherKey, .tick] {
            let out = m.handle(event, at: 0)
            #expect(out.swallow == false, "\(event)")
            #expect(out.effects.isEmpty, "\(event)")
        }
        #expect(m.state == .idle)
    }

    @Test func optionTabArmsAndSwallows() {
        var m = make()
        let out = m.handle(.tab(reverse: false, windowCount: 4), at: 0)
        #expect(m.state == .armed)
        #expect(m.selection == 1)
        #expect(out.swallow)
        #expect(out.effects.isEmpty, "armed must not show the panel yet")
    }

    @Test func optionShiftTabArmsOnLastWindow() {
        var m = make()
        _ = m.handle(.tab(reverse: true, windowCount: 4), at: 0)
        #expect(m.selection == 3)
    }

    @Test func zeroWindowsStaysIdleButSwallows() {
        var m = make()
        let out = m.handle(.tab(reverse: false, windowCount: 0), at: 0)
        #expect(m.state == .idle)
        #expect(out.swallow)
        #expect(out.effects.isEmpty)
    }

    @Test func quickTapCommitsWithoutShowingPanel() {
        var m = make()
        _ = m.handle(.tab(reverse: false, windowCount: 3), at: 0)
        _ = m.handle(.tick, at: 0.05)
        let out = m.handle(.optionReleased, at: 0.06)
        #expect(out.effects == [.commit(1)])
        #expect(out.swallow == false, "Option flagsChanged is never swallowed")
        #expect(m.state == .idle)
    }

    @Test func tickBeforeDelayDoesNothing() {
        var m = make(delay: 0.1)
        _ = m.handle(.tab(reverse: false, windowCount: 3), at: 1.0)
        let out = m.handle(.tick, at: 1.099)
        #expect(out.effects.isEmpty)
        #expect(m.state == .armed)
    }

    @Test func tickAfterDelayShowsPanelOnce() {
        var m = make(delay: 0.1)
        _ = m.handle(.tab(reverse: false, windowCount: 3), at: 1.0)
        let first = m.handle(.tick, at: 1.1)
        #expect(first.effects == [.show(selection: 1)])
        #expect(m.state == .shown)
        let second = m.handle(.tick, at: 1.2)
        #expect(second.effects.isEmpty)
    }

    @Test func releaseWhileShownCommitsSelection() {
        var m = make()
        _ = m.handle(.tab(reverse: false, windowCount: 3), at: 0)
        _ = m.handle(.tick, at: 0.2)
        _ = m.handle(.tab(reverse: false, windowCount: 3), at: 0.3)
        #expect(m.selection == 2)
        let out = m.handle(.optionReleased, at: 0.4)
        #expect(out.effects == [.commit(2)])
        #expect(m.state == .idle)
    }

    @Test func returnCommitsAndSwallows() {
        var m = make()
        _ = m.handle(.tab(reverse: false, windowCount: 3), at: 0)
        _ = m.handle(.tick, at: 0.2)
        let out = m.handle(.returnKey, at: 0.3)
        #expect(out.effects == [.commit(1)])
        #expect(out.swallow)
        #expect(m.state == .idle)
    }

    @Test func escapeCancelsFromArmedAndShown() {
        var armed = make()
        _ = armed.handle(.tab(reverse: false, windowCount: 3), at: 0)
        let a = armed.handle(.escape, at: 0.01)
        #expect(a.effects == [.cancel])
        #expect(a.swallow)
        #expect(armed.state == .idle)

        var shown = make()
        _ = shown.handle(.tab(reverse: false, windowCount: 3), at: 0)
        _ = shown.handle(.tick, at: 0.2)
        let s = shown.handle(.escape, at: 0.3)
        #expect(s.effects == [.cancel])
        #expect(shown.state == .idle)
    }

    @Test func optionReleaseAfterCancelDoesNotCommit() {
        var m = make()
        _ = m.handle(.tab(reverse: false, windowCount: 3), at: 0)
        _ = m.handle(.escape, at: 0.01)
        let out = m.handle(.optionReleased, at: 0.02)
        #expect(out.effects.isEmpty)
    }

    @Test func tabAdvancesAndWraps() {
        var m = make()
        _ = m.handle(.tab(reverse: false, windowCount: 3), at: 0)    // 1
        _ = m.handle(.tab(reverse: false, windowCount: 3), at: 0.01) // 2
        _ = m.handle(.tab(reverse: false, windowCount: 3), at: 0.02) // 0
        #expect(m.selection == 0)
        _ = m.handle(.tab(reverse: true, windowCount: 3), at: 0.03)  // 2
        #expect(m.selection == 2)
    }

    @Test func tabWhileShownEmitsSelectionChanged() {
        var m = make()
        _ = m.handle(.tab(reverse: false, windowCount: 3), at: 0)
        _ = m.handle(.tick, at: 0.2)
        let out = m.handle(.tab(reverse: false, windowCount: 3), at: 0.3)
        #expect(out.effects == [.selectionChanged(2)])
    }

    @Test func tabWhileArmedDoesNotEmitEffects() {
        var m = make()
        _ = m.handle(.tab(reverse: false, windowCount: 3), at: 0)
        let out = m.handle(.tab(reverse: false, windowCount: 3), at: 0.01)
        #expect(out.effects.isEmpty)
        #expect(m.selection == 2)
    }

    @Test func arrowsMoveAndShowImmediatelyFromArmed() {
        var m = make()
        _ = m.handle(.tab(reverse: false, windowCount: 4), at: 0) // 1
        let out = m.handle(.arrow(.next), at: 0.01)               // 2
        #expect(out.swallow)
        #expect(out.effects == [.show(selection: 2)])
        #expect(m.state == .shown)
        let back = m.handle(.arrow(.previous), at: 0.02)
        #expect(back.effects == [.selectionChanged(1)])
    }

    @Test func arrowsWrap() {
        var m = make()
        _ = m.handle(.tab(reverse: false, windowCount: 3), at: 0) // 1
        _ = m.handle(.arrow(.previous), at: 0.01)                 // 0
        _ = m.handle(.arrow(.previous), at: 0.02)                 // 2
        #expect(m.selection == 2)
        _ = m.handle(.arrow(.next), at: 0.03)                     // 0
        #expect(m.selection == 0)
    }

    @Test func otherKeysSwallowedWhileOpen() {
        var m = make()
        _ = m.handle(.tab(reverse: false, windowCount: 3), at: 0)
        let out = m.handle(.otherKey, at: 0.01)
        #expect(out.swallow)
        #expect(out.effects.isEmpty)
        #expect(m.state == .armed)
    }

    @Test func tabKeyUpSwallowedAfterSwallowedTabDown() {
        var m = make()
        _ = m.handle(.tab(reverse: false, windowCount: 3), at: 0)
        _ = m.handle(.optionReleased, at: 0.01) // quick tap commits first
        let up = m.handle(.tabKeyUp, at: 0.02)
        #expect(up.swallow, "tab key-up must not leak after its key-down was swallowed")
        let again = m.handle(.tabKeyUp, at: 0.03)
        #expect(again.swallow == false, "flag clears after one key-up")
    }

    @Test func tabKeyUpPassesThroughWhenNeverSwallowed() {
        var m = make()
        #expect(m.handle(.tabKeyUp, at: 0).swallow == false)
    }

    @Test func canReArmAfterCommit() {
        var m = make()
        _ = m.handle(.tab(reverse: false, windowCount: 3), at: 0)
        _ = m.handle(.optionReleased, at: 0.01)
        _ = m.handle(.tab(reverse: false, windowCount: 5), at: 1)
        #expect(m.state == .armed)
        #expect(m.selection == 1)
    }

    @Test func forceResetReturnsToIdle() {
        var m = make()
        _ = m.handle(.tab(reverse: false, windowCount: 3), at: 0)
        m.reset()
        #expect(m.state == .idle)
    }
}
