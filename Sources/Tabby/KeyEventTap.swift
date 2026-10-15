import CoreGraphics
import Foundation

/// Session-wide keyboard (and mouse-button) event tap on its own thread, so a slow main thread never makes macOS
/// disable the tap. The callback does no work itself: it forwards to `handler` and swallows the
/// event when `handler` returns true.
final class KeyEventTap {
    /// Runs on the tap thread. Return true to swallow the event.
    var handler: ((CGEventType, CGEvent) -> Bool)?
    /// Runs on the tap thread after macOS disabled the tap and we turned it back on.
    var onReenabled: (() -> Void)?

    private(set) var port: CFMachPort?
    private var runLoop: CFRunLoop?

    var isRunning: Bool { port != nil }

    /// Returns false when the tap cannot be created (no Accessibility permission yet).
    func start() -> Bool {
        guard port == nil else { return true }
        let ready = DispatchSemaphore(value: 0)
        var created = false
        let thread = Thread { [self] in
            let mask = (1 << CGEventType.keyDown.rawValue)
                | (1 << CGEventType.keyUp.rawValue)
                | (1 << CGEventType.flagsChanged.rawValue)
                | (1 << CGEventType.leftMouseDown.rawValue)
                | (1 << CGEventType.leftMouseUp.rawValue)
                | (1 << CGEventType.rightMouseDown.rawValue)
                | (1 << CGEventType.rightMouseUp.rawValue)
            guard let p = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(mask),
                callback: KeyEventTap.callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else {
                ready.signal()
                return
            }
            let loop = CFRunLoopGetCurrent()
            port = p
            runLoop = loop
            CFRunLoopAddSource(loop, CFMachPortCreateRunLoopSource(nil, p, 0), .commonModes)
            CGEvent.tapEnable(tap: p, enable: true)
            created = true
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "tabby.eventtap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        return created
    }

    func stop() {
        if let p = port {
            CGEvent.tapEnable(tap: p, enable: false)
            CFMachPortInvalidate(p)
        }
        if let loop = runLoop { CFRunLoopStop(loop) }
        port = nil
        runLoop = nil
    }

    private static let callback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return Unmanaged.passUnretained(event) }
        let tap = Unmanaged<KeyEventTap>.fromOpaque(refcon).takeUnretainedValue()
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let p = tap.port { CGEvent.tapEnable(tap: p, enable: true) }
            tap.onReenabled?()
            return Unmanaged.passUnretained(event)
        default:
            return (tap.handler?(type, event) ?? false) ? nil : Unmanaged.passUnretained(event)
        }
    }
}
