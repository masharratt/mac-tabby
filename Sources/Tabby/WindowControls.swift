import AppKit
import ApplicationServices
import TabbyCore

/// What a hover control can do to a window. Each needs the window's Accessibility element.
enum ItemAction {
    case close, minimize, toggleFullScreen, quitApp
}

/// Window actions behind the hover controls. All return whether the request was accepted; the
/// target app may still refuse (a "save changes?" sheet, for example).
enum WindowControls {
    private static let fullScreenAttribute = "AXFullScreen"

    /// Other-desktop windows are not in the AX list until focused once, so they get no controls.
    static func isAvailable(_ window: WindowInfo) -> Bool {
        !window.isOnOtherDesktop && AXWindows.element(for: window) != nil
    }

    static func close(_ window: WindowInfo) -> Bool {
        guard let element = AXWindows.element(for: window) else { return false }
        var button: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXCloseButtonAttribute as CFString, &button) == .success,
              let button, CFGetTypeID(button) == AXUIElementGetTypeID() else { return false }
        return AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString) == .success
    }

    /// Toggles; returns the new minimized state, or nil when the request failed.
    static func toggleMinimized(_ window: WindowInfo) -> Bool? {
        guard let element = AXWindows.element(for: window) else { return nil }
        let target = !(AXWindows.bool(element, kAXMinimizedAttribute) ?? window.isMinimized)
        let value: CFTypeRef = target ? kCFBooleanTrue! : kCFBooleanFalse!
        guard AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, value) == .success else { return nil }
        return target
    }

    static func toggleFullScreen(_ window: WindowInfo) -> Bool {
        guard let element = AXWindows.element(for: window) else { return false }
        let target = !(AXWindows.bool(element, fullScreenAttribute) ?? false)
        let value: CFTypeRef = target ? kCFBooleanTrue! : kCFBooleanFalse!
        return AXUIElementSetAttributeValue(element, fullScreenAttribute as CFString, value) == .success
    }

    static func quitApp(_ window: WindowInfo) -> Bool {
        NSRunningApplication(processIdentifier: window.pid)?.terminate() ?? false
    }
}
