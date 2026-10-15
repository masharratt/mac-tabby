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
    /// Panel frame in global top-left coordinates while it is on screen; nil otherwise.
    private var panelFrame: CGRect?
    /// Mouse-down types whose matching mouse-up must be swallowed too.
    private var swallowedUps: Set<CGEventType> = []

    init(source: WindowSource, settings: Settings) {
        self.source = source
        machine = SwitcherStateMachine(showDelay: settings.showDelay)
    }

    var isIdle: Bool { locked { machine.state == .idle } }

    func apply(_ settings: Settings) {
        locked { machine.showDelay = settings.showDelay }
    }

    func reset() {
        locked {
            machine.reset()
            panelFrame = nil
            swallowedUps = []
        }
    }

    /// Main thread. Tells the tap where the panel is so it can tell "outside" clicks from item clicks.
    func setPanelFrame(_ frame: CGRect?) { locked { panelFrame = frame } }

    func snapshot() -> (windows: [WindowInfo], selection: Int) { locked { (windows, machine.selection) } }

    /// Main thread: pointer entered an item.
    func hover(_ index: Int) { feed(.hover(index)) }

    /// Main thread: click landed on an item.
    func itemClick(_ index: Int) { feed(.itemClick(index)) }

    /// Main thread: these windows were closed or their app quit; the list shrinks in place.
    func removeWindows(ids: Set<UInt32>) {
        let indices: [Int] = locked {
            let hit = windows.indices.filter { ids.contains(windows[$0].id) }
            for i in hit.reversed() { windows.remove(at: i) }
            return hit
        }
        if !indices.isEmpty { feed(.windowsRemoved(indices)) }
    }

    /// Main thread: edit one window's flags (e.g. minimized) without changing the selection.
    func updateWindow(id: UInt32, _ edit: (inout WindowInfo) -> Void) {
        locked {
            if let i = windows.firstIndex(where: { $0.id == id }) { edit(&windows[i]) }
        }
    }

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
        case .leftMouseDown, .rightMouseDown:
            return mouseDown(type, at: event.location)
        case .leftMouseUp, .rightMouseUp:
            let down: CGEventType = type == .leftMouseUp ? .leftMouseDown : .rightMouseDown
            return locked { swallowedUps.remove(down) != nil }
        default:
            return false
        }
    }

    /// A click outside the visible panel cancels the switcher. It is swallowed (with its mouse-up)
    /// so the click does not also activate or press something in the app underneath.
    private func mouseDown(_ type: CGEventType, at point: CGPoint) -> Bool {
        let outside = locked { machine.state == .shown && panelFrame.map { !$0.contains(point) } == true }
        guard outside else { return false }
        let swallow = feed(.outsideClick)
        if swallow { locked { _ = swallowedUps.insert(type) } }
        return swallow
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
