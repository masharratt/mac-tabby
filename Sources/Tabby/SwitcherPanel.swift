import AppKit
import TabbyCore

/// The Titles-list switcher panel. Non-activating so it never steals focus from the current app.
/// P3 adds thumbnail and app-icon layouts behind the same show/update/hide surface.
final class SwitcherPanel: NSPanel {
    private static let rowHeight: CGFloat = 32
    private static let padding: CGFloat = 10
    private static let maxWidth: CGFloat = 640

    private let background = NSVisualEffectView()
    private var windows: [WindowInfo] = []
    private var icons: [pid_t: NSImage] = [:]

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.masksToBounds = true
        contentView = background
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(windows: [WindowInfo], selection: Int) {
        self.windows = windows
        icons = [:]
        for w in windows where icons[w.pid] == nil {
            icons[w.pid] = NSRunningApplication(processIdentifier: w.pid)?.icon
        }
        let screen = Self.screenUnderMouse()
        let area = screen.visibleFrame
        let capacity = max(1, Int((area.height * 0.9 - Self.padding * 2) / Self.rowHeight))
        let rows = min(windows.count, capacity)
        let size = NSSize(
            width: min(Self.maxWidth, area.width * 0.9),
            height: CGFloat(rows) * Self.rowHeight + Self.padding * 2
        )
        setFrame(NSRect(
            x: area.midX - size.width / 2,
            y: area.midY - size.height / 2,
            width: size.width,
            height: size.height
        ), display: false)
        rebuildRows(selection: selection, capacity: capacity)
        orderFrontRegardless()
    }

    func updateSelection(_ selection: Int) {
        guard isVisible else { return }
        let capacity = max(1, Int((frame.height - Self.padding * 2) / Self.rowHeight))
        rebuildRows(selection: selection, capacity: capacity)
    }

    func hide() {
        orderOut(nil)
        background.subviews.forEach { $0.removeFromSuperview() }
        windows = []
        icons = [:]
    }

    private func rebuildRows(selection: Int, capacity: Int) {
        background.subviews.forEach { $0.removeFromSuperview() }
        let range = SelectionIndex.visibleRange(count: windows.count, selected: selection, capacity: capacity)
        for (slot, index) in range.enumerated() {
            let y = frame.height - Self.padding - CGFloat(slot + 1) * Self.rowHeight
            let row = RowView(
                frame: NSRect(x: Self.padding, y: y, width: frame.width - Self.padding * 2, height: Self.rowHeight),
                title: windows[index].displayTitle,
                icon: icons[windows[index].pid],
                selected: index == selection
            )
            background.addSubview(row)
        }
    }

    private static func screenUnderMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }
}

private final class RowView: NSView {
    init(frame: NSRect, title: String, icon: NSImage?, selected: Bool) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 8
        if selected { layer?.backgroundColor = NSColor.selectedContentBackgroundColor.cgColor }

        let iconView = NSImageView(frame: NSRect(x: 8, y: (frame.height - 22) / 2, width: 22, height: 22))
        iconView.image = icon
        addSubview(iconView)

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 14)
        label.textColor = selected ? .alternateSelectedControlTextColor : .labelColor
        label.lineBreakMode = .byTruncatingTail
        let h = label.intrinsicContentSize.height
        label.frame = NSRect(x: 38, y: (frame.height - h) / 2, width: frame.width - 46, height: h)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("not used") }
}
