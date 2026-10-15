import AppKit
import TabbyCore

/// The switcher panel. Non-activating so it never steals focus from the current app.
/// Layout math lives in TabbyCore (`PanelGeometry`); this class only places views.
final class SwitcherPanel: NSPanel {
    /// Cached thumbnail lookup; must only read memory.
    var imageProvider: ((UInt32) -> CGImage?)?
    /// Pointer moved onto the item at this index (only after the pointer really moved).
    var onHover: ((Int) -> Void)?
    var onClickItem: ((Int) -> Void)?
    var onAction: ((ItemAction, Int) -> Void)?
    /// Whether hover controls make sense for a window (needs an AX element). May call AX.
    var controlsAvailable: ((WindowInfo) -> Bool)?

    private let background = NSVisualEffectView()
    private var windows: [WindowInfo] = []
    private var icons: [pid_t: NSImage] = [:]
    private var layout = Layout.thumbnails
    private var thumbnailSize = ThumbnailSize.medium
    private var showWindowTitles = true
    private var grid: GridLayout?
    private var items: [Int: SwitcherItemView] = [:]
    private var selection = 0
    private var screenSize = CGSize.zero
    private var hoveredIndex: Int?
    private var controlsCache: [UInt32: Bool] = [:]
    /// Pointer position when the panel opened: a panel appearing under a still pointer must not
    /// select whatever item happens to be there.
    private var openMouse = CGPoint.zero

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
        showWindowTitles = settings.showWindowTitles
    }

    func show(windows: [WindowInfo], selection: Int) {
        self.windows = windows
        self.selection = selection
        icons = [:]
        controlsCache = [:]
        hoveredIndex = nil
        openMouse = NSEvent.mouseLocation
        let area = Self.screenUnderMouse().visibleFrame
        screenSize = area.size
        relayout(around: area)
        orderFrontRegardless()
    }

    /// The list changed in place (a window closed, minimized, ...): redraw and keep the panel
    /// centred on the same screen.
    func reload(windows: [WindowInfo], selection: Int) {
        guard isVisible else { return }
        self.windows = windows
        self.selection = selection
        relayout(around: Self.screen(containing: frame)?.visibleFrame ?? Self.screenUnderMouse().visibleFrame)
    }

    /// Panel frame in global top-left coordinates (what CGEvent locations use).
    var globalFrame: CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return PreviewRules.appKitRect(fromGlobal: frame, primaryScreenHeight: primaryHeight) // the flip is its own inverse
    }

    private func relayout(around area: NSRect) {
        for w in windows where icons[w.pid] == nil {
            icons[w.pid] = NSRunningApplication(processIdentifier: w.pid)?.icon
        }
        let g = makeGrid()
        grid = g
        setFrame(NSRect(x: area.midX - g.panelSize.width / 2, y: area.midY - g.panelSize.height / 2,
                        width: g.panelSize.width, height: g.panelSize.height), display: false)
        rebuildItems()
    }

    func updateSelection(_ selection: Int) {
        guard isVisible, let old = grid else { return }
        self.selection = selection
        let g = makeGrid()
        grid = g
        if g.visibleRows == old.visibleRows {
            for (index, view) in items { view.setSelected(index == selection) }
            refreshControls()
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
        hoveredIndex = nil
        controlsCache = [:]
    }

    // MARK: Hover controls

    private func hover(_ index: Int) {
        guard NSEvent.mouseLocation != openMouse else { return }
        hoveredIndex = index
        refreshControls()
        onHover?(index)
    }

    /// Controls show on the item that is both hovered and selected, and only when AX can reach it.
    private func refreshControls() {
        for (index, view) in items {
            let wanted = index == hoveredIndex && index == selection && windows.indices.contains(index)
            view.setControlsVisible(wanted && hasControls(windows[index]))
        }
    }

    private func hasControls(_ w: WindowInfo) -> Bool {
        if let cached = controlsCache[w.id] { return cached }
        let available = controlsAvailable?(w) ?? false
        controlsCache[w.id] = available
        return available
    }

    /// After a rebuild, find what is under the pointer (only once the pointer has moved).
    private func indexUnderMouse() -> Int? {
        guard NSEvent.mouseLocation != openMouse else { return nil }
        let point = background.convert(mouseLocationOutsideOfEventStream, from: nil)
        return items.first { $0.value.frame.contains(point) }?.key
    }

    private func makeGrid() -> GridLayout {
        PanelGeometry.grid(count: windows.count, selected: selection, layout: layout,
                           thumbnailSize: thumbnailSize, screen: screenSize, showWindowTitles: showWindowTitles)
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
            view.index = index
            view.onHover = { [weak self, weak view] in if let view { self?.hover(view.index) } }
            view.onClick = { [weak self, weak view] in if let view { self?.onClickItem?(view.index) } }
            view.onAction = { [weak self, weak view] action in if let view { self?.onAction?(action, view.index) } }
            view.setSelected(index == selection)
            background.addSubview(view)
            items[index] = view
        }
        hoveredIndex = indexUnderMouse()
        refreshControls()
    }

    private func makeItem(for w: WindowInfo, frame: NSRect) -> SwitcherItemView {
        let icon = icons[w.pid]
        switch layout {
        case .titles:
            return RowItemView(frame: frame, window: w, marker: Self.marker(for: w), icon: icon)
        case .appIcons, .thumbnails:
            return TileItemView(frame: frame, window: w, layout: layout, thumbnailSize: thumbnailSize,
                                showWindowTitles: showWindowTitles, marker: Self.marker(for: w), icon: icon, thumbnail: imageProvider?(w.id))
        }
    }

    /// Small tag: minimized wins over other desktop (a minimized window has no desktop).
    private static func marker(for w: WindowInfo) -> String? {
        if w.isMinimized { return "Minimized" }
        if w.isOnOtherDesktop { return "Other desktop" }
        return nil
    }

    private static func screen(containing rect: NSRect) -> NSScreen? {
        NSScreen.screens.first { $0.frame.intersects(rect) }
    }

    private static func screenUnderMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }
}
