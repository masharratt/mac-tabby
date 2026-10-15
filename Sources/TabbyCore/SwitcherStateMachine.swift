import Foundation

public enum SwitcherState: Equatable, Sendable {
    /// Nothing happening; every key passes through.
    case idle
    /// Option+Tab seen; the panel is not visible yet (a quick tap never flashes it).
    case armed
    /// Panel visible.
    case shown
}

public enum SwitcherDirection: Equatable, Sendable {
    case next, previous
}

public enum SwitcherEvent: Equatable, Sendable {
    /// Tab pressed with Option held. Arms when idle, otherwise moves the selection.
    case tab(reverse: Bool, windowCount: Int)
    case tabKeyUp
    case optionReleased
    case returnKey
    case escape
    case arrow(SwitcherDirection)
    /// Any other key press.
    case otherKey
    /// Periodic clock tick; drives the show delay.
    case tick
}

public enum SwitcherEffect: Equatable, Sendable {
    case show(selection: Int)
    case selectionChanged(Int)
    /// Focus the window at this index and hide the panel.
    case commit(Int)
    /// Hide the panel, focus nothing.
    case cancel
}

public struct SwitcherOutput: Equatable, Sendable {
    /// Whether the event tap should swallow the originating keystroke.
    public var swallow: Bool
    public var effects: [SwitcherEffect]
}

/// Keyboard state machine for the switcher. Pure: time is passed in, effects are returned.
public struct SwitcherStateMachine: Sendable {
    public private(set) var state: SwitcherState = .idle
    public private(set) var selection = 0
    public var showDelay: TimeInterval

    private var windowCount = 0
    private var armedAt: TimeInterval = 0
    private var swallowNextTabUp = false

    public init(showDelay: TimeInterval = 0.1) {
        self.showDelay = showDelay
    }

    /// Drop back to idle without effects (permission lost, tap restarted, ...).
    public mutating func reset() {
        state = .idle
        selection = 0
        windowCount = 0
        swallowNextTabUp = false
    }

    public mutating func handle(_ event: SwitcherEvent, at now: TimeInterval) -> SwitcherOutput {
        switch state {
        case .idle: return handleIdle(event, at: now)
        case .armed, .shown: return handleOpen(event, at: now)
        }
    }

    private mutating func handleIdle(_ event: SwitcherEvent, at now: TimeInterval) -> SwitcherOutput {
        switch event {
        case let .tab(reverse, count):
            swallowNextTabUp = true
            guard count > 0 else { return SwitcherOutput(swallow: true, effects: []) }
            windowCount = count
            selection = SelectionIndex.initial(count: count, reverse: reverse)
            armedAt = now
            state = .armed
            return SwitcherOutput(swallow: true, effects: [])
        case .tabKeyUp:
            return SwitcherOutput(swallow: consumeTabUp(), effects: [])
        default:
            return SwitcherOutput(swallow: false, effects: [])
        }
    }

    private mutating func handleOpen(_ event: SwitcherEvent, at now: TimeInterval) -> SwitcherOutput {
        switch event {
        case let .tab(reverse, _):
            swallowNextTabUp = true
            return move(reverse ? .previous : .next, showNow: false)
        case let .arrow(direction):
            return move(direction, showNow: true)
        case .tabKeyUp:
            return SwitcherOutput(swallow: consumeTabUp(), effects: [])
        case .optionReleased:
            return finish(.commit(selection), swallow: false)
        case .returnKey:
            return finish(.commit(selection), swallow: true)
        case .escape:
            return finish(.cancel, swallow: true)
        case .otherKey:
            return SwitcherOutput(swallow: true, effects: [])
        case .tick:
            if state == .armed, now - armedAt >= showDelay {
                state = .shown
                return SwitcherOutput(swallow: false, effects: [.show(selection: selection)])
            }
            return SwitcherOutput(swallow: false, effects: [])
        }
    }

    private mutating func move(_ direction: SwitcherDirection, showNow: Bool) -> SwitcherOutput {
        selection = direction == .next
            ? SelectionIndex.next(selection, count: windowCount)
            : SelectionIndex.previous(selection, count: windowCount)
        if state == .armed {
            guard showNow else { return SwitcherOutput(swallow: true, effects: []) }
            state = .shown
            return SwitcherOutput(swallow: true, effects: [.show(selection: selection)])
        }
        return SwitcherOutput(swallow: true, effects: [.selectionChanged(selection)])
    }

    private mutating func finish(_ effect: SwitcherEffect, swallow: Bool) -> SwitcherOutput {
        state = .idle
        windowCount = 0
        return SwitcherOutput(swallow: swallow, effects: [effect])
    }

    private mutating func consumeTabUp() -> Bool {
        defer { swallowNextTabUp = false }
        return swallowNextTabUp
    }
}
