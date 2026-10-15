import Testing
@testable import TabbyCore

@Suite struct ThumbnailCacheTests {
    typealias Cache = ThumbnailCache<String>

    @Test func defaultBudgetIs64MB() {
        #expect(Cache().budget == 64 * 1024 * 1024)
    }

    @Test func byteCostIsRGBA() {
        #expect(Cache.bytes(width: 200, height: 100) == 80_000)
        #expect(Cache.bytes(width: 0, height: 100) == 0)
    }

    @Test func storesAndReturns() {
        var c = Cache(budget: 100)
        #expect(c.store("a", bytes: 40, trusted: true, for: 1) == .stored(evicted: []))
        #expect(c.value(for: 1) == "a")
        #expect(c.totalBytes == 40)
        #expect(c.value(for: 2) == nil)
    }

    @Test func evictsLeastRecentlyUsedFirst() {
        var c = Cache(budget: 100)
        _ = c.store("a", bytes: 40, trusted: true, for: 1)
        _ = c.store("b", bytes: 40, trusted: true, for: 2)
        let r = c.store("c", bytes: 40, trusted: true, for: 3)
        #expect(r == .stored(evicted: [1]))
        #expect(c.ids == [2, 3], "ids=\(c.ids)")
        #expect(c.totalBytes <= c.budget)
    }

    @Test func readingRefreshesRecency() {
        var c = Cache(budget: 100)
        _ = c.store("a", bytes: 40, trusted: true, for: 1)
        _ = c.store("b", bytes: 40, trusted: true, for: 2)
        _ = c.value(for: 1)
        let r = c.store("c", bytes: 40, trusted: true, for: 3)
        #expect(r == .stored(evicted: [2]))
    }

    @Test func evictsSeveralWhenNeeded() {
        var c = Cache(budget: 100)
        for i in 1...4 { _ = c.store("x", bytes: 25, trusted: true, for: UInt32(i)) }
        let r = c.store("big", bytes: 60, trusted: true, for: 9)
        #expect(r == .stored(evicted: [1, 2, 3]))
        #expect(c.totalBytes == 85)
    }

    @Test func oversizeImageIsRejectedWithoutEvicting() {
        var c = Cache(budget: 100)
        _ = c.store("a", bytes: 40, trusted: true, for: 1)
        #expect(c.store("huge", bytes: 101, trusted: true, for: 2) == .rejectedOversize)
        #expect(c.ids == [1])
    }

    @Test func replacingSameWindowDoesNotDoubleCount() {
        var c = Cache(budget: 100)
        _ = c.store("a", bytes: 60, trusted: true, for: 1)
        #expect(c.store("a2", bytes: 70, trusted: true, for: 1) == .stored(evicted: []))
        #expect(c.totalBytes == 70)
        #expect(c.value(for: 1) == "a2")
    }

    @Test func untrustedCaptureNeverOverwritesCachedImage() {
        var c = Cache(budget: 100)
        _ = c.store("good", bytes: 10, trusted: true, for: 1)
        #expect(c.store("offscreen", bytes: 10, trusted: false, for: 1) == .rejectedUntrusted)
        #expect(c.value(for: 1) == "good")
        #expect(c.totalBytes == 10)
    }

    @Test func untrustedCaptureFillsAnEmptySlotAndTrustedReplacesIt() {
        var c = Cache(budget: 100)
        #expect(c.store("maybe", bytes: 10, trusted: false, for: 1) == .stored(evicted: []))
        #expect(c.store("real", bytes: 10, trusted: true, for: 1) == .stored(evicted: []))
        #expect(c.value(for: 1) == "real")
    }

    @Test func removeFreesBytes() {
        var c = Cache(budget: 100)
        _ = c.store("a", bytes: 40, trusted: true, for: 1)
        c.remove(1)
        #expect(c.totalBytes == 0)
        #expect(c.value(for: 1) == nil)
        c.remove(1)
        #expect(c.totalBytes == 0)
    }

    @Test func pruneEvictsClosedWindows() {
        var c = Cache(budget: 1000)
        for i in 1...4 { _ = c.store("x", bytes: 10, trusted: true, for: UInt32(i)) }
        let gone = c.prune(keeping: [2, 4, 99])
        #expect(gone == [1, 3], "gone=\(gone)")
        #expect(c.ids == [2, 4])
        #expect(c.totalBytes == 20)
    }
}
