import AppKit
import TabbyCore

/// One window in the switcher. Subclasses draw a list row or a grid tile.
class SwitcherItemView: NSView {
    let windowID: UInt32
    private(set) var isSelectedItem = false

    /// Position in the window list; set by the panel.
    var index = 0
    /// Pointer entered or moved over the item.
    var onHover: (() -> Void)?
    var onClick: (() -> Void)?
    var onAction: ((ItemAction) -> Void)?
    /// Row layouts centre the controls on the right edge; tiles put them in the top-right corner.
    var controlsAreCompact: Bool { false }
    private var controls: ItemControlsView?

    init(frame: NSRect, windowID: UInt32) {
        self.windowID = windowID
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Highlight: filled background plus an accent outline, clear in light and dark mode.
    func setSelected(_ selected: Bool) {
        isSelectedItem = selected
        layer?.backgroundColor = selected ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.85).cgColor : nil
        layer?.borderWidth = selected ? 2 : 0
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        restyleText()
    }

    func setThumbnail(_ image: CGImage?) {}
    func restyleText() {}

    func setControlsVisible(_ visible: Bool) {
        guard visible else { controls?.isHidden = true; return }
        if controls == nil {
            let view = ItemControlsView { [weak self] in self?.onAction?($0) }
            controls = view
            addSubview(view)
        }
        guard let controls else { return }
        let size = controls.fittingSize
        let y = controlsAreCompact ? (bounds.height - size.height) / 2 : bounds.height - size.height - 6
        controls.frame = NSRect(x: bounds.width - size.width - 6, y: y, width: size.width, height: size.height)
        controls.isHidden = false
    }

    // MARK: Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }
    override func mouseEntered(with event: NSEvent) { onHover?() }
    override func mouseMoved(with event: NSEvent) { onHover?() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    var primaryTextColor: NSColor { isSelectedItem ? .alternateSelectedControlTextColor : .labelColor }
    var secondaryTextColor: NSColor { isSelectedItem ? .alternateSelectedControlTextColor : .secondaryLabelColor }
}

/// Titles layout: icon, "App - Title", optional right-aligned tag.
final class RowItemView: SwitcherItemView {
    private let label: NSTextField
    private let markerLabel: NSTextField?

    override var controlsAreCompact: Bool { true }

    init(frame: NSRect, window: WindowInfo, marker: String?, icon: NSImage?) {
        label = NSTextField(labelWithString: window.displayTitle)
        markerLabel = marker.map { NSTextField(labelWithString: $0) }
        super.init(frame: frame, windowID: window.id)
        layer?.cornerRadius = 8

        let iconView = NSImageView(frame: NSRect(x: 8, y: (frame.height - 22) / 2, width: 22, height: 22))
        iconView.image = icon
        addSubview(iconView)

        label.font = .systemFont(ofSize: 14)
        label.lineBreakMode = .byTruncatingTail
        let h = label.intrinsicContentSize.height
        var labelWidth = frame.width - 46
        if let markerLabel {
            markerLabel.font = .systemFont(ofSize: 11)
            let size = markerLabel.intrinsicContentSize
            markerLabel.frame = NSRect(x: frame.width - 8 - size.width, y: (frame.height - size.height) / 2,
                               width: size.width, height: size.height)
            addSubview(markerLabel)
            labelWidth -= size.width + 8
        }
        label.frame = NSRect(x: 38, y: (frame.height - h) / 2, width: labelWidth, height: h)
        addSubview(label)
        restyleText()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func restyleText() {
        label.textColor = primaryTextColor
        markerLabel?.textColor = secondaryTextColor
    }
}

/// Thumbnails and App Icons layouts: a picture area with the title under it (truncated).
final class TileItemView: SwitcherItemView {
    private let label: NSTextField
    private let thumbView = NSImageView()
    private let iconView = NSImageView()
    private let markerLabel: NSTextField?
    private let showsThumbnails: Bool

    init(frame: NSRect, window: WindowInfo, layout: Layout, thumbnailSize: ThumbnailSize, showWindowTitles: Bool,
         marker: String?, icon: NSImage?, thumbnail: CGImage?) {
        showsThumbnails = layout == .thumbnails
        let iconTitles = layout == .appIcons && showWindowTitles
        let text = layout == .thumbnails ? window.displayTitle
            : (iconTitles && !window.title.isEmpty ? window.title : window.appName)
        label = NSTextField(labelWithString: text)
        markerLabel = marker.map { NSTextField(labelWithString: $0) }
        super.init(frame: frame, windowID: window.id)

        let labelH: CGFloat = iconTitles ? 34 : 18   // two lines when showing window titles
        let inset: CGFloat = 8
        let picture: NSRect
        if layout == .thumbnails {
            let box = thumbnailSize.box
            picture = NSRect(x: inset, y: frame.height - inset - box.height, width: box.width, height: box.height)
        } else {
            picture = NSRect(x: 0, y: labelH + 10, width: frame.width, height: frame.height - labelH - 18)
        }

        thumbView.frame = picture
        thumbView.imageScaling = .scaleProportionallyUpOrDown
        thumbView.wantsLayer = true
        thumbView.layer?.cornerRadius = 6
        thumbView.layer?.masksToBounds = true
        addSubview(thumbView)

        // The app icon is the placeholder until a thumbnail lands, and the picture in App Icons.
        let side = layout == .thumbnails ? min(64, picture.height * 0.6) : min(64, picture.height)
        iconView.frame = NSRect(x: picture.midX - side / 2, y: picture.midY - side / 2, width: side, height: side)
        iconView.image = icon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)

        if let markerLabel {
            markerLabel.font = .systemFont(ofSize: 10, weight: .medium)
            markerLabel.textColor = .white
            markerLabel.wantsLayer = true
            markerLabel.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
            markerLabel.layer?.cornerRadius = 4
            let s = markerLabel.intrinsicContentSize
            markerLabel.frame = NSRect(x: picture.minX + 4, y: picture.maxY - s.height - 4, width: s.width + 6, height: s.height)
            markerLabel.alignment = .center
            addSubview(markerLabel)
        }

        label.font = .systemFont(ofSize: 12)
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        if iconTitles {
            label.maximumNumberOfLines = 2
            label.cell?.wraps = true
            label.cell?.truncatesLastVisibleLine = true
        }
        label.frame = NSRect(x: inset, y: 8, width: frame.width - 2 * inset, height: labelH)
        addSubview(label)

        if layout == .thumbnails { setThumbnail(thumbnail) } else { thumbView.isHidden = true }
        restyleText()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func setThumbnail(_ image: CGImage?) {
        guard showsThumbnails else { return }
        thumbView.image = image.map { NSImage(cgImage: $0, size: .zero) }
        thumbView.isHidden = image == nil
        iconView.isHidden = image != nil
    }

    override func restyleText() { label.textColor = primaryTextColor }
}

/// Small row of window controls shown over the hovered item: close, minimize, full screen, quit app.
final class ItemControlsView: NSView {
    private static let buttons: [(ItemAction, String, String)] = [
        (.close, "xmark.circle.fill", "Close window"),
        (.minimize, "minus.circle.fill", "Minimize or restore window"),
        (.toggleFullScreen, "arrow.up.left.and.arrow.down.right.circle.fill", "Toggle full screen"),
        (.quitApp, "power.circle.fill", "Quit app"),
    ]
    private static let side: CGFloat = 20
    private static let pad: CGFloat = 4

    init(onAction: @escaping (ItemAction) -> Void) {
        let n = CGFloat(Self.buttons.count)
        let size = NSSize(width: n * Self.side + (n + 1) * Self.pad, height: Self.side + 2 * Self.pad)
        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        layer?.cornerRadius = size.height / 2
        for (i, spec) in Self.buttons.enumerated() {
            let button = ControlButton(action: spec.0, symbol: spec.1, tip: spec.2, onPress: onAction)
            button.frame = NSRect(x: Self.pad + CGFloat(i) * (Self.side + Self.pad), y: Self.pad, width: Self.side, height: Self.side)
            addSubview(button)
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var fittingSize: NSSize { frame.size }
}

/// Borderless symbol button that works on the first click inside the non-activating panel.
private final class ControlButton: NSButton {
    private let onPress: (ItemAction) -> Void
    private let itemAction: ItemAction

    init(action: ItemAction, symbol: String, tip: String, onPress: @escaping (ItemAction) -> Void) {
        itemAction = action
        self.onPress = onPress
        super.init(frame: .zero)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyUpOrDown
        isBordered = false
        contentTintColor = .white
        toolTip = tip
        setAccessibilityLabel(tip)
        target = self
        self.action = #selector(pressed)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    @objc private func pressed() { onPress(itemAction) }
}
