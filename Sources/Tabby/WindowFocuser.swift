import AppKit
import ApplicationServices
import TabbyCore

/// Brings a window to the front using public Accessibility + AppKit APIs.
/// P2 adds the private-API path for windows on other Spaces (see PrivateAPI.swift, not yet written).
enum WindowFocuser {
    static func focus(_ window: WindowInfo) {
        let app = AXUIElementCreateApplication(window.pid)
        if let axWindow = matchingAXWindow(for: window, in: app) {
            AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
        }
        AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        NSRunningApplication(processIdentifier: window.pid)?.activate()
    }

    /// Matches by frame first (titles can repeat), then by title.
    private static func matchingAXWindow(for window: WindowInfo, in app: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let axWindows = value as? [AXUIElement] else { return nil }
        if let byFrame = axWindows.first(where: { frame(of: $0).map { near($0, window.bounds) } ?? false }) {
            return byFrame
        }
        guard !window.title.isEmpty else { return nil }
        return axWindows.first { string($0, kAXTitleAttribute) == window.title }
    }

    private static func near(_ a: CGRect, _ b: CGRect) -> Bool {
        let t: CGFloat = 2
        return abs(a.minX - b.minX) <= t && abs(a.minY - b.minY) <= t
            && abs(a.width - b.width) <= t && abs(a.height - b.height) <= t
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var pos: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &pos) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let pos, let size else { return nil }
        var p = CGPoint.zero
        var s = CGSize.zero
        guard AXValueGetValue(pos as! AXValue, .cgPoint, &p),
              AXValueGetValue(size as! AXValue, .cgSize, &s) else { return nil }
        return CGRect(origin: p, size: s)
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
