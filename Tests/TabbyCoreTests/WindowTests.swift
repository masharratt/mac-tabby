import Testing
@testable import TabbyCore

@Suite struct WindowInfoTests {
    @Test func displayTitleUsesAppNameWhenTitleEmpty() {
        let w = WindowInfo(id: 1, pid: 10, appName: "Safari", title: "")
        #expect(w.displayTitle == "Safari")
    }

    @Test func displayTitleCombinesAppAndTitle() {
        let w = WindowInfo(id: 1, pid: 10, appName: "Safari", title: "Apple")
        #expect(w.displayTitle == "Safari \u{2014} Apple")
    }

    @Test func displayTitleDoesNotRepeatIdenticalTitle() {
        let w = WindowInfo(id: 1, pid: 10, appName: "Finder", title: "Finder")
        #expect(w.displayTitle == "Finder")
    }
}
