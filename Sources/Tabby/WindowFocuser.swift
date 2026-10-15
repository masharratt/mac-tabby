import AppKit
import ApplicationServices
import TabbyCore

/// Brings a window to the front. Preferred path: unminimize via AX when reachable, then the
/// SkyLight call that works across Spaces, then AXRaise. Fallback when any private symbol is
/// missing or the call fails: public activate + AXRaise (current Space only).
enum WindowFocuser {
    /// Called with the window id after a focus attempt so MRU order updates immediately.
    static var onFocused: ((UInt32) -> Void)?

    static func focus(_ window: WindowInfo) {
        let app = AXWindows.application(window.pid)
        let axWindow = matchingAXWindow(for: window, in: app)
        if let axWindow, AXWindows.bool(axWindow, kAXMinimizedAttribute) == true {
            AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        let usedSkyLight = PrivateAPI.bringToFront(pid: window.pid, windowID: window.id)
        if let axWindow {
            AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
        }
        if !usedSkyLight {
            AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            NSRunningApplication(processIdentifier: window.pid)?.activate()
        }
        onFocused?(window.id)
    }

    /// Matches by window id when the private call works, else frame, then title.
    /// Off-Space windows are not in the AX list, so this returns nil for them.
    private static func matchingAXWindow(for window: WindowInfo, in app: AXUIElement) -> AXUIElement? {
        let axWindows = AXWindows.windows(of: app)
        if let byID = axWindows.first(where: { PrivateAPI.windowID(of: $0) == window.id }) { return byID }
        if let byFrame = axWindows.first(where: { AXWindows.frame(of: $0).map { near($0, window.bounds) } ?? false }) {
            return byFrame
        }
        guard !window.title.isEmpty else { return nil }
        return axWindows.first { AXWindows.string($0, kAXTitleAttribute) == window.title }
    }

    private static func near(_ a: CGRect, _ b: CGRect) -> Bool {
        let t: CGFloat = 2
        return abs(a.minX - b.minX) <= t && abs(a.minY - b.minY) <= t
            && abs(a.width - b.width) <= t && abs(a.height - b.height) <= t
    }
}
