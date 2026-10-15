import CoreGraphics
import Testing
@testable import TabbyCore

@Suite struct WindowInventoryTests {
    private func rec(
        _ id: UInt32, pid: Int32 = 10, app: String = "Safari", bundle: String? = "com.apple.Safari",
        title: String = "Page", w: CGFloat = 800, h: CGFloat = 600, layer: Int = 0,
        onScreen: Bool = true, regular: Bool = true, appHidden: Bool = false
    ) -> WindowRecord {
        WindowRecord(id: id, pid: pid, appName: app, bundleID: bundle, title: title,
                     bounds: CGRect(x: 0, y: 0, width: w, height: h), layer: layer,
                     isOnScreen: onScreen, ownerIsRegular: regular, isAppHidden: appHidden)
    }
    private func ids(_ ws: [WindowInfo]) -> [UInt32] { ws.map(\.id) }
    private let own: Int32 = 999

    // MARK: filtering

    @Test func keepsOrdinaryWindow() {
        #expect(ids(WindowInventoryRules.merge([rec(1)], ax: [:], ownPID: own)) == [1])
    }

    @Test func dropsNonZeroLayer() {
        #expect(WindowInventoryRules.merge([rec(1, layer: 25)], ax: [:], ownPID: own).isEmpty)
    }

    @Test func dropsTinyWindows() {
        let out = WindowInventoryRules.merge([rec(1, w: 39, h: 600), rec(2, w: 800, h: 10)], ax: [:], ownPID: own)
        #expect(out.isEmpty)
    }

    @Test func keepsWindowExactlyAtMinimumSide() {
        let out = WindowInventoryRules.merge([rec(1, w: 40, h: 40)], ax: [:], ownPID: own)
        #expect(ids(out) == [1])
    }

    @Test func dropsNonRegularApps() {
        #expect(WindowInventoryRules.merge([rec(1, regular: false)], ax: [:], ownPID: own).isEmpty)
    }

    @Test func dropsOwnWindows() {
        #expect(WindowInventoryRules.merge([rec(1, pid: own)], ax: [:], ownPID: own).isEmpty)
    }

    @Test func dropsUntitledOffScreenWindows() {
        #expect(WindowInventoryRules.merge([rec(1, title: "", onScreen: false)], ax: [:], ownPID: own).isEmpty)
    }

    @Test func keepsUntitledOnScreenWindows() {
        #expect(ids(WindowInventoryRules.merge([rec(1, title: "")], ax: [:], ownPID: own)) == [1])
    }

    // MARK: SC + AX merge

    @Test func offScreenWithoutAXIsOtherDesktop() {
        let w = WindowInventoryRules.merge([rec(1, onScreen: false)], ax: [:], ownPID: own)[0]
        #expect(w.isOnOtherDesktop)
        #expect(!w.isMinimized)
    }

    @Test func offScreenAXMinimizedIsMinimizedNotOtherDesktop() {
        let ax: [Int32: [AXWindowRecord]] = [10: [AXWindowRecord(windowID: 1, isMinimized: true)]]
        let w = WindowInventoryRules.merge([rec(1, onScreen: false)], ax: ax, ownPID: own)[0]
        #expect(w.isMinimized)
        #expect(!w.isOnOtherDesktop)
    }

    @Test func untitledMinimizedWindowIsKept() {
        let ax: [Int32: [AXWindowRecord]] = [10: [AXWindowRecord(windowID: 1, isMinimized: true)]]
        #expect(ids(WindowInventoryRules.merge([rec(1, title: "", onScreen: false)], ax: ax, ownPID: own)) == [1])
    }

    @Test func axMatchesByWindowIDNotPid() {
        let ax: [Int32: [AXWindowRecord]] = [10: [AXWindowRecord(windowID: 2, isMinimized: true)]]
        let out = WindowInventoryRules.merge([rec(1, onScreen: false), rec(2, onScreen: false)], ax: ax, ownPID: own)
        #expect(out.first { $0.id == 1 }?.isMinimized == false)
        #expect(out.first { $0.id == 2 }?.isMinimized == true)
    }

    @Test func axWindowWithoutResolvedIDIsIgnored() {
        let ax: [Int32: [AXWindowRecord]] = [10: [AXWindowRecord(windowID: nil, isMinimized: true)]]
        let w = WindowInventoryRules.merge([rec(1, onScreen: false)], ax: ax, ownPID: own)[0]
        #expect(!w.isMinimized)
    }

    @Test func hiddenAppWindowIsNeitherMinimizedNorOtherDesktop() {
        let w = WindowInventoryRules.merge([rec(1, onScreen: false, appHidden: true)], ax: [:], ownPID: own)[0]
        #expect(w.isAppHidden)
        #expect(!w.isOnOtherDesktop)
        #expect(!w.isMinimized)
    }

    @Test func onScreenWindowHasNoMarkers() {
        let w = WindowInventoryRules.merge([rec(1)], ax: [:], ownPID: own)[0]
        #expect(!w.isOnOtherDesktop && !w.isMinimized && !w.isAppHidden)
    }

    @Test func preservesInputOrderAndMetadata() {
        let out = WindowInventoryRules.merge([rec(3, app: "Mail"), rec(1)], ax: [:], ownPID: own)
        #expect(ids(out) == [3, 1])
        #expect(out[0].appName == "Mail")
        #expect(out[0].bundleID == "com.apple.Safari")
    }

    // MARK: settings filter

    private func infos() -> [WindowInfo] {
        var a = WindowInfo(id: 1, pid: 1, appName: "Safari", title: "a"); a.bundleID = "com.apple.Safari"
        var b = WindowInfo(id: 2, pid: 2, appName: "Mail", title: "b"); b.isMinimized = true
        var c = WindowInfo(id: 3, pid: 3, appName: "Notes", title: "c"); c.isOnOtherDesktop = true
        return [a, b, c]
    }

    @Test func defaultSettingsShowEverything() {
        #expect(ids(WindowInventoryRules.visible(infos(), settings: Settings())) == [1, 2, 3])
    }

    @Test func showMinimizedOffHidesMinimized() {
        var s = Settings(); s.showMinimized = false
        #expect(ids(WindowInventoryRules.visible(infos(), settings: s)) == [1, 3])
    }

    @Test func showOtherDesktopsOffHidesOtherDesktop() {
        var s = Settings(); s.showOtherDesktops = false
        #expect(ids(WindowInventoryRules.visible(infos(), settings: s)) == [1, 2])
    }

    @Test func hiddenAppsMatchNameCaseInsensitively() {
        var s = Settings(); s.hiddenApps = ["safari"]
        #expect(ids(WindowInventoryRules.visible(infos(), settings: s)) == [2, 3])
    }

    @Test func hiddenAppsMatchBundleID() {
        var s = Settings(); s.hiddenApps = ["com.apple.Safari"]
        #expect(ids(WindowInventoryRules.visible(infos(), settings: s)) == [2, 3])
    }

    @Test func showHiddenAppsOffHidesHiddenAppWindows() {
        var h = WindowInfo(id: 4, pid: 4, appName: "Preview", title: "d"); h.isAppHidden = true
        let all = infos() + [h]
        #expect(ids(WindowInventoryRules.visible(all, settings: Settings())) == [1, 2, 3, 4])
        var s = Settings(); s.showHiddenApps = false
        #expect(ids(WindowInventoryRules.visible(all, settings: s)) == [1, 2, 3])
    }
}
