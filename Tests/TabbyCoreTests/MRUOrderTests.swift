import Testing
@testable import TabbyCore

@Suite struct MRUOrderTests {
    private func w(_ id: UInt32) -> WindowInfo { WindowInfo(id: id, pid: 1, appName: "A", title: "t\(id)") }
    private func ids(_ ws: [WindowInfo]) -> [UInt32] { ws.map(\.id) }

    @Test func seedDefinesInitialOrder() {
        let mru = MRUOrder(seed: [3, 1, 2])
        #expect(ids(mru.ordered([w(1), w(2), w(3)])) == [3, 1, 2])
    }

    @Test func focusMovesWindowToFront() {
        var mru = MRUOrder(seed: [3, 1, 2])
        mru.focused(2)
        #expect(ids(mru.ordered([w(1), w(2), w(3)])) == [2, 3, 1])
    }

    @Test func focusingSameWindowTwiceDoesNotDuplicate() {
        var mru = MRUOrder(seed: [1, 2])
        mru.focused(2)
        mru.focused(2)
        #expect(mru.order == [2, 1])
    }

    @Test func unknownWindowsComeAfterKnownInIncomingOrder() {
        let mru = MRUOrder(seed: [5])
        #expect(ids(mru.ordered([w(8), w(5), w(7)])) == [5, 8, 7])
    }

    @Test func closedWindowsDropOutOfOutput() {
        var mru = MRUOrder(seed: [1, 2, 3])
        mru.focused(3)
        #expect(ids(mru.ordered([w(1), w(3)])) == [3, 1])
    }

    // Bug: every inventory refresh pruned ids missing from that one listing. A window focused just
    // before a refresh that had not listed it yet (new window, full-screen transition, listing
    // without Screen Recording) lost its rank and came back at the very end of the switcher.
    @Test func windowMissingFromOneListingKeepsItsRankWhenItReturns() {
        var mru = MRUOrder(seed: [1, 2, 3])
        mru.focused(9)
        #expect(ids(mru.ordered([w(1), w(2), w(3)])) == [1, 2, 3])
        #expect(ids(mru.ordered([w(1), w(2), w(3), w(9)])) == [9, 1, 2, 3])
    }

    @Test func focusedWindowNotYetListedLeadsWhenItAppears() {
        var mru = MRUOrder(seed: [1, 2])
        mru.focused(9)
        #expect(ids(mru.ordered([w(1), w(2), w(9)])) == [9, 1, 2])
    }

    @Test func orderIsBounded() {
        var mru = MRUOrder(seed: [])
        for i in 0..<(MRUOrder.capacity + 50) { mru.focused(UInt32(i)) }
        #expect(mru.order.count == MRUOrder.capacity)
        #expect(mru.order.first == UInt32(MRUOrder.capacity + 49))
    }
}
