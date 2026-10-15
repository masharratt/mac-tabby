import Testing
@testable import TabbyCore

@Suite struct SelectionIndexTests {
    @Test func nextWraps() {
        #expect(SelectionIndex.next(0, count: 3) == 1)
        #expect(SelectionIndex.next(2, count: 3) == 0)
    }

    @Test func previousWraps() {
        #expect(SelectionIndex.previous(1, count: 3) == 0)
        #expect(SelectionIndex.previous(0, count: 3) == 2)
    }

    @Test func singleItemStaysPut() {
        #expect(SelectionIndex.next(0, count: 1) == 0)
        #expect(SelectionIndex.previous(0, count: 1) == 0)
    }

    @Test func emptyListReturnsZero() {
        #expect(SelectionIndex.next(0, count: 0) == 0)
        #expect(SelectionIndex.previous(0, count: 0) == 0)
    }

    @Test func initialSelectionSkipsCurrentWindow() {
        #expect(SelectionIndex.initial(count: 4, reverse: false) == 1)
        #expect(SelectionIndex.initial(count: 4, reverse: true) == 3)
        #expect(SelectionIndex.initial(count: 1, reverse: false) == 0)
        #expect(SelectionIndex.initial(count: 1, reverse: true) == 0)
    }

    @Test func visibleRangeFitsEverythingWhenSmall() {
        #expect(SelectionIndex.visibleRange(count: 3, selected: 2, capacity: 10) == 0..<3)
    }

    @Test func visibleRangeKeepsSelectionInside() {
        for selected in 0..<20 {
            let r = SelectionIndex.visibleRange(count: 20, selected: selected, capacity: 7)
            #expect(r.count == 7, "selected=\(selected) range=\(r)")
            #expect(r.contains(selected), "selected=\(selected) range=\(r)")
            #expect(r.lowerBound >= 0 && r.upperBound <= 20)
        }
    }

    @Test func visibleRangeEmptyWhenNoCapacity() {
        #expect(SelectionIndex.visibleRange(count: 5, selected: 0, capacity: 0).isEmpty)
    }
}
