import AppKit
import TabbyCore

/// The switcher panel. Non-activating so it never steals focus from the current app.
/// Layout math lives in TabbyCore (`PanelGeometry`); this class only places views.
final class SwitcherPanel: NSPanel {
    /// Cached thumbnail lookup; must only read memory.
    var imageProvider: ((UInt32) -> CGImage?)?

    private let background = NSVisualEffectView()
    private var windows: [WindowInfo] = []
    private var icons: [pid_t: NSImage] = [:]
    private var layout = Layout.thumbnails
    private var thumbnailSize = ThumbnailSize.medium
    private var grid: GridLayout?
    private var items: [Int: SwitcherItemView] = [:]
    private var selection = 0
    private var screenSize = CGSize.zero

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
        background.layer?.cornerRadius = 16
        background.layer?.masksToBounds = true
        contentView = background
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Takes effect the next time the panel opens.
    func apply(_ settings: Settings) {
        layout = settings.layout
        thumbnailSize = settings.thumbnailSize
    }

    func show(windows: [WindowInfo], selection: Int) {
        self.windows = windows
        self.selection = selection
        icons = [:]
        for w in windows where icons[w.pid] == nil {
            icons[w.pid] = NSRunningApplication(processIdentifier: w.pid)?.icon
        }
        let area = Self.screenUnderMouse().visibleFrame
        screenSize = area.size
        let g = makeGrid()
        grid = g
        setFrame(NSRect(x: area.midX - g.panelSize.width / 2, y: area.midY - g.panelSize.height / 2,
                        width: g.panelSize.width, height: g.panelSize.height), display: false)
        rebuildItems()
        orderFrontRegardless()
    }

    func updateSelection(_ selection: Int) {
        guard isVisible, let old = grid else { return }
        self.selection = selection
        let g = makeGrid()
        grid = g
        if g.visibleRows == old.visibleRows {
            for (index, view) in items { view.setSelected(index == selection) }
        } else {
            rebuildItems()
        }
    }

    /// A new thumbnail landed in the cache: swap it into its tile.
    func thumbnailUpdated(_ id: UInt32) {
        guard isVisible, layout == .thumbnails else { return }
        for view in items.values where view.windowID == id { view.setThumbnail(imageProvider?(id)) }
    }

    func hide() {
        orderOut(nil)
        background.subviews.forEach { $0.removeFromSuperview() }
        windows = []
        icons = [:]
        items = [:]
        grid = nil
    }

    private func makeGrid() -> GridLayout {
        PanelGeometry.grid(count: windows.count, selected: selection, layout: layout,
                           thumbnailSize: thumbnailSize, screen: screenSize)
    }

    private func rebuildItems() {
        background.subviews.forEach { $0.removeFromSuperview() }
        items = [:]
        guard let g = grid else { return }
        for index in g.itemRange {
            guard let slot = g.slot(of: index) else { continue }
            let origin = g.origin(row: slot.row, column: slot.column)
            let frame = NSRect(x: origin.x, y: g.panelSize.height - origin.y - g.cellSize.height,
                               width: g.cellSize.width, height: g.cellSize.height)
            let view = makeItem(for: windows[index], frame: frame)
            view.setSelected(index == selection)
            background.addSubview(view)
            items[index] = view
        }
    }

    private func makeItem(for w: WindowInfo, frame: NSRect) -> SwitcherItemView {
        let icon = icons[w.pid]
        switch layout {
        case .titles:
            return RowItemView(frame: frame, window: w, marker: Self.marker(for: w), icon: icon)
        case .appIcons, .thumbnails:
            return TileItemView(frame: frame, window: w, layout: layout, thumbnailSize: thumbnailSize,
                                marker: Self.marker(for: w), icon: icon, thumbnail: imageProvider?(w.id))
        }
    }

    /// Small tag: minimized wins over other desktop (a minimized window has no desktop).
    private static func marker(for w: WindowInfo) -> String? {
        if w.isMinimized { return "Minimized" }
        if w.isOnOtherDesktop { return "Other desktop" }
        return nil
    }

    private static func screenUnderMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }
}
