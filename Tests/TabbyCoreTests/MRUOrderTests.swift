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

    @Test func pruneForgetsClosedWindows() {
        var mru = MRUOrder(seed: [1, 2, 3])
        mru.prune(keeping: [1, 3])
        #expect(mru.order == [1, 3])
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
