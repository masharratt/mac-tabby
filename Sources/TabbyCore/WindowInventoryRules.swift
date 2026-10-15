import CoreGraphics
import Foundation

/// A raw window record from the OS inventory (ScreenCaptureKit), before filtering.
public struct WindowRecord: Equatable, Sendable {
    public var id: UInt32
    public var pid: Int32
    public var appName: String
    public var bundleID: String?
    public var title: String
    public var bounds: CGRect
    public var layer: Int
    public var isOnScreen: Bool
    /// Owner is a regular (Dock-visible) app.
    public var ownerIsRegular: Bool
    /// Owner app is hidden (Cmd+H).
    public var isAppHidden: Bool
    /// Ids of the Spaces the window belongs to; nil when the private lookup is unavailable.
    /// Ordered-out helper windows belong to none.
    public var spaceIDs: [Int]?

    public init(id: UInt32, pid: Int32, appName: String, bundleID: String?, title: String, bounds: CGRect,
                layer: Int, isOnScreen: Bool, ownerIsRegular: Bool, isAppHidden: Bool, spaceIDs: [Int]? = nil) {
        self.id = id; self.pid = pid; self.appName = appName; self.bundleID = bundleID
        self.title = title; self.bounds = bounds; self.layer = layer
        self.isOnScreen = isOnScreen; self.ownerIsRegular = ownerIsRegular; self.isAppHidden = isAppHidden; self.spaceIDs = spaceIDs
    }
}

/// What Accessibility says about one window of an app. AX only lists windows of the current Space.
public struct AXWindowRecord: Equatable, Sendable {
    /// Resolved through the private window-id call; nil when unavailable.
    public var windowID: UInt32?
    public var isMinimized: Bool

    public init(windowID: UInt32?, isMinimized: Bool) {
        self.windowID = windowID
        self.isMinimized = isMinimized
    }
}

public enum WindowInventoryRules {
    public static let minimumSide: CGFloat = 40

    /// Filters raw records (layer 0, sane size, regular app, not Tabby) and merges AX data.
    /// An off-screen window is: minimized if AX says so, else hidden-app if its app is hidden,
    /// else on another desktop. Untitled off-screen windows are dropped as helper junk unless
    /// AX confirmed them as minimized. Off-screen windows known to be on no Space (spaceCount == 0)
    /// are phantom ordered-out helpers and are dropped unless AX says minimized. Off-screen windows
    /// whose Spaces are all currently visible (one per display) are ordered-out leftovers of the
    /// visible desktop and are dropped unless minimized or the app is hidden. `visibleSpaces` nil
    /// (lookup unavailable) keeps off-screen windows that have Spaces. Input order is preserved.
    public static func merge(_ records: [WindowRecord], ax: [Int32: [AXWindowRecord]], ownPID: Int32,
                             visibleSpaces: Set<Int>? = nil) -> [WindowInfo] {
        var result: [WindowInfo] = []
        for r in records {
            guard r.layer == 0, r.ownerIsRegular, r.pid != ownPID,
                  r.bounds.width >= minimumSide, r.bounds.height >= minimumSide else { continue }
            let axMinimized = ax[r.pid]?.contains { $0.windowID == r.id && $0.isMinimized } ?? false
            let minimized = !r.isOnScreen && axMinimized
            let hidden = !r.isOnScreen && !minimized && r.isAppHidden
            let otherDesktop = !r.isOnScreen && !minimized && !hidden
            if !r.isOnScreen, r.title.isEmpty, !minimized { continue }
            if !r.isOnScreen, let spaces = r.spaceIDs, !minimized {
                if spaces.isEmpty { continue }
                if !r.isAppHidden, let visible = visibleSpaces, spaces.allSatisfy(visible.contains) { continue }
            }
            var w = WindowInfo(id: r.id, pid: r.pid, appName: r.appName, title: r.title, bounds: r.bounds)
            w.bundleID = r.bundleID
            w.isMinimized = minimized
            w.isAppHidden = hidden
            w.isOnOtherDesktop = otherDesktop
            result.append(w)
        }
        return result
    }

    /// Applies user settings: hidden-apps list (name or bundle id, case-insensitive) and the
    /// show-minimized / show-other-desktops toggles.
    public static func visible(_ windows: [WindowInfo], settings: Settings) -> [WindowInfo] {
        let blocked = Set(settings.hiddenApps.map { $0.lowercased() })
        return windows.filter { w in
            if blocked.contains(w.appName.lowercased()) { return false }
            if let b = w.bundleID, blocked.contains(b.lowercased()) { return false }
            if !settings.showMinimized, w.isMinimized { return false }
            if !settings.showOtherDesktops, w.isOnOtherDesktop { return false }
            if !settings.showHiddenApps, w.isAppHidden { return false }
            return true
        }
    }
}
