import ApplicationServices
import CoreGraphics
import TabbyCore

/// Thin Accessibility helpers shared by the inventory, focus and MRU tracking.
enum AXWindows {
    /// A hung app must not stall a refresh or a focus; fail the call after this long.
    static let messagingTimeout: Float = 0.25

    static func application(_ pid: pid_t) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        return app
    }

    static func windows(of app: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    static func records(pid: pid_t) -> [AXWindowRecord] {
        windows(of: application(pid)).map {
            AXWindowRecord(windowID: PrivateAPI.windowID(of: $0), isMinimized: bool($0, kAXMinimizedAttribute) ?? false)
        }
    }

    /// The window currently focused in the app, as a CGWindowID (needs the private id call).
    static func focusedWindowID(pid: pid_t) -> UInt32? {
        let app = application(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return PrivateAPI.windowID(of: value as! AXUIElement)
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? Bool
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    static func frame(of element: AXUIElement) -> CGRect? {
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
}
