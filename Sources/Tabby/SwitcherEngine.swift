import Carbon.HIToolbox
import CoreGraphics
import Foundation
import TabbyCore

/// Bridges raw key events to the pure state machine. Thread-safe: the event tap thread feeds key
/// events, the main thread feeds clock ticks. Effects go to `onEffect` on the main queue.
final class SwitcherEngine {
    /// Called on the main queue with the effect and the window list it refers to.
    var onEffect: ((SwitcherEffect, [WindowInfo]) -> Void)?
    /// Called on the main queue when Option+Tab arms the switcher from idle.
    var onArmed: (() -> Void)?

    private let lock = NSLock()
    private var machine: SwitcherStateMachine
    private var windows: [WindowInfo] = []
    private let source: WindowSource

    init(source: WindowSource, settings: Settings) {
        self.source = source
        machine = SwitcherStateMachine(showDelay: settings.showDelay)
    }

    var isIdle: Bool { locked { machine.state == .idle } }

    func apply(_ settings: Settings) {
        locked { machine.showDelay = settings.showDelay }
    }

    func reset() { locked { machine.reset() } }

    /// Event tap thread. Returns true when the keystroke must be swallowed.
    func process(_ type: CGEventType, _ event: CGEvent) -> Bool {
        let flags = event.flags
        switch type {
        case .flagsChanged:
            if !flags.contains(.maskAlternate) { feed(.optionReleased) }
            return false
        case .keyUp:
            guard event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_Tab) else { return false }
            return feed(.tabKeyUp)
        case .keyDown:
            return keyDown(code: Int(event.getIntegerValueField(.keyboardEventKeycode)), flags: flags)
        default:
            return false
        }
    }

    /// Main thread, ~25 ms while the switcher is armed or shown.
    func tick(optionHeld: Bool) {
        if !optionHeld { feed(.optionReleased) }
        feed(.tick)
    }

    private func keyDown(code: Int, flags: CGEventFlags) -> Bool {
        let idle = isIdle
        if code == kVK_Tab {
            if idle {
                // Only a bare Option(+Shift) chord arms the switcher; Cmd+Tab etc. pass through.
                guard flags.contains(.maskAlternate),
                      !flags.contains(.maskCommand), !flags.contains(.maskControl) else { return false }
                return arm(reverse: flags.contains(.maskShift))
            }
            return feed(.tab(reverse: flags.contains(.maskShift), windowCount: locked { windows.count }))
        }
        if idle { return false }
        switch code {
        case kVK_Escape: return feed(.escape)
        case kVK_Return, kVK_ANSI_KeypadEnter: return feed(.returnKey)
        case kVK_LeftArrow, kVK_UpArrow: return feed(.arrow(.previous))
        case kVK_RightArrow, kVK_DownArrow: return feed(.arrow(.next))
        default: return feed(.otherKey)
        }
    }

    /// Runs on the tap thread: `source` must only read its cache, never query the OS.
    private func arm(reverse: Bool) -> Bool {
        if IsSecureEventInputEnabled() { return false }
        let list = source.currentWindows()
        locked { windows = list }
        let swallow = feed(.tab(reverse: reverse, windowCount: list.count))
        if !isIdle { DispatchQueue.main.async { [self] in onArmed?() } }
        return swallow
    }

    @discardableResult
    private func feed(_ event: SwitcherEvent) -> Bool {
        let (out, snapshot) = locked { () -> (SwitcherOutput, [WindowInfo]) in
            (machine.handle(event, at: ProcessInfo.processInfo.systemUptime), windows)
        }
        for effect in out.effects {
            DispatchQueue.main.async { [self] in onEffect?(effect, snapshot) }
        }
        return out.swallow
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
