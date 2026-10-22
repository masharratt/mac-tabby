import CoreGraphics
import Testing
@testable import TabbyCore

@Suite struct SwitcherMouseTests {
    func shown(count: Int = 4) -> SwitcherStateMachine {
        var m = SwitcherStateMachine(showDelay: 0.1)
        _ = m.handle(.tab(reverse: false, windowCount: count), at: 0)
        _ = m.handle(.tick, at: 0.2)
        return m
    }

    @Test func outsideClickCancelsAndSwallowsWhenShown() {
        var m = shown()
        let out = m.handle(.outsideClick, at: 0.3)
        #expect(out.effects == [.cancel])
        #expect(out.swallow)
        #expect(m.state == .idle)
    }

    @Test func outsideClickIgnoredWhenIdleOrArmed() {
        var idle = SwitcherStateMachine()
        let a = idle.handle(.outsideClick, at: 0)
        #expect(a.effects.isEmpty)
        #expect(a.swallow == false)

        var armed = SwitcherStateMachine(showDelay: 0.1)
        _ = armed.handle(.tab(reverse: false, windowCount: 3), at: 0)
        let b = armed.handle(.outsideClick, at: 0.01)
        #expect(b.effects.isEmpty, "panel is not visible while armed, so a click is not outside it")
        #expect(b.swallow == false)
        #expect(armed.state == .armed)
    }

    @Test func itemClickCommitsThatItem() {
        var m = shown()
        let out = m.handle(.itemClick(3), at: 0.3)
        #expect(out.effects == [.commit(3)])
        #expect(out.swallow)
        #expect(m.state == .idle)
    }

    @Test func itemClickOutOfRangeIsIgnored() {
        var m = shown(count: 3)
        for bad in [-1, 3, 99] {
            let out = m.handle(.itemClick(bad), at: 0.3)
            #expect(out.effects.isEmpty, "index \(bad)")
        }
        #expect(m.state == .shown)
    }

    @Test func releasingOptionAfterItemClickDoesNothing() {
        var m = shown()
        _ = m.handle(.itemClick(2), at: 0.3)
        #expect(m.handle(.optionReleased, at: 0.4).effects.isEmpty)
    }

    // Pointer hover is deliberately not a switcher event: a panel opening under a resting pointer
    // used to steal the selection, so releasing Option focused the wrong window. Only a click picks.
    @Test func optionReleaseCommitsKeyboardSelectionWhateverThePointerIsOver() {
        var m = shown()
        #expect(m.handle(.optionReleased, at: 0.3).effects == [.commit(1)])
    }

    @Test func removingSelectedMiddleItemKeepsNeighbourSelected() {
        var m = shown(count: 4)
        _ = m.handle(.arrow(.next), at: 0.3)
        let out = m.handle(.windowsRemoved([2]), at: 0.4)
        #expect(out.effects == [.listChanged(selection: 2)])
        #expect(m.selection == 2)
        // count is now 3: wrap-around proves the machine tracks the new size
        _ = m.handle(.arrow(.next), at: 0.5)
        _ = m.handle(.arrow(.next), at: 0.6)
        #expect(m.selection == 1)
    }

    @Test func removingEarlierItemShiftsSelectionDown() {
        var m = shown(count: 4)
        _ = m.handle(.arrow(.next), at: 0.3)
        _ = m.handle(.arrow(.next), at: 0.3)
        _ = m.handle(.windowsRemoved([0]), at: 0.4)
        #expect(m.selection == 2)
    }

    @Test func removingEverythingCancels() {
        var m = shown(count: 2)
        let out = m.handle(.windowsRemoved([0, 1]), at: 0.3)
        #expect(out.effects == [.cancel])
        #expect(m.state == .idle)
    }

    @Test func removalWhileIdleIsIgnored() {
        var m = SwitcherStateMachine()
        #expect(m.handle(.windowsRemoved([0]), at: 0).effects.isEmpty)
    }
}

@Suite struct SelectionRemovalTests {
    @Test func selectedLastItemRemovedSelectsNewLast() {
        #expect(SelectionIndex.afterRemoval(selected: 3, removed: [3], count: 4) == 2)
    }

    @Test func selectedItemRemovedSelectsItsSuccessor() {
        #expect(SelectionIndex.afterRemoval(selected: 1, removed: [1], count: 4) == 1)
    }

    @Test func unselectedRemovalBeforeShiftsDown() {
        #expect(SelectionIndex.afterRemoval(selected: 2, removed: [0, 1], count: 4) == 0)
    }

    @Test func unselectedRemovalAfterLeavesSelection() {
        #expect(SelectionIndex.afterRemoval(selected: 1, removed: [2, 3], count: 4) == 1)
    }

    @Test func removingSelectionAndTailClampsToNewLast() {
        #expect(SelectionIndex.afterRemoval(selected: 2, removed: [2, 3], count: 4) == 1)
    }

    @Test func allRemovedReturnsNil() {
        #expect(SelectionIndex.afterRemoval(selected: 0, removed: [0, 1], count: 2) == nil)
    }

    @Test func outOfRangeIndicesAreIgnored() {
        #expect(SelectionIndex.afterRemoval(selected: 1, removed: [9, -1], count: 3) == 1)
    }

    @Test func nothingRemoved() {
        #expect(SelectionIndex.afterRemoval(selected: 2, removed: [], count: 3) == 2)
        #expect(SelectionIndex.remainingCount(count: 3, removed: [1, 1, 8]) == 2)
    }
}

@Suite struct PreviewRulesTests {
    func window(_ edit: (inout WindowInfo) -> Void = { _ in }) -> WindowInfo {
        var w = WindowInfo(id: 1, pid: 1, appName: "A", title: "t", bounds: CGRect(x: 10, y: 20, width: 300, height: 200))
        edit(&w)
        return w
    }

    @Test func visibleWindowGetsItsFrame() {
        #expect(PreviewRules.outlineFrame(for: window()) == CGRect(x: 10, y: 20, width: 300, height: 200))
    }

    @Test func minimizedOtherDesktopHiddenAndEmptyGetNoOutline() {
        #expect(PreviewRules.outlineFrame(for: window { $0.isMinimized = true }) == nil)
        #expect(PreviewRules.outlineFrame(for: window { $0.isOnOtherDesktop = true }) == nil)
        #expect(PreviewRules.outlineFrame(for: window { $0.isAppHidden = true }) == nil)
        #expect(PreviewRules.outlineFrame(for: window { $0.bounds = .zero }) == nil)
    }

    @Test func flipsGlobalTopLeftToAppKitBottomLeft() {
        let cg = CGRect(x: 10, y: 20, width: 300, height: 200)
        #expect(PreviewRules.appKitRect(fromGlobal: cg, primaryScreenHeight: 1000)
                == CGRect(x: 10, y: 780, width: 300, height: 200))
    }

    @Test func outlineScreenIsTheOneWithMostOverlap() {
        let screens = [CGRect(x: 0, y: 0, width: 1000, height: 800), CGRect(x: 1000, y: 0, width: 1000, height: 800)]
        #expect(PreviewRules.screenIndex(for: CGRect(x: 900, y: 0, width: 400, height: 100), among: screens) == 1)
        #expect(PreviewRules.screenIndex(for: CGRect(x: 100, y: 0, width: 400, height: 100), among: screens) == 0)
        #expect(PreviewRules.screenIndex(for: CGRect(x: 5000, y: 0, width: 10, height: 10), among: screens) == nil)
    }
}
