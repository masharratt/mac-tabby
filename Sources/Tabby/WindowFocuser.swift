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
        let axWindow = AXWindows.element(for: window)
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
}
