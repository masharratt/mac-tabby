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
    /// Row layouts centre the controls on the right edge; tiles put them over the picture.
    var controlsAreCompact: Bool { false }
    /// Tiles: traffic lights sit at this area's top-left, quit at its top-right.
    var controlsAnchor: NSRect { bounds }
    private var lights: ControlClusterView?
    private var quit: ControlClusterView?

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

    /// `forceGlyphs` draws the hover glyphs without a pointer (README renders).
    func setControlsVisible(_ visible: Bool, forceGlyphs: Bool = false) {
        guard visible else { lights?.isHidden = true; quit?.isHidden = true; return }
        if lights == nil {
            let press: (ItemAction) -> Void = { [weak self] in self?.onAction?($0) }
            let l = ControlClusterView(specs: ControlClusterView.trafficLights, glyphsOnHoverOnly: true, onAction: press)
            let q = ControlClusterView(specs: [ControlClusterView.quitSpec], glyphsOnHoverOnly: false, onAction: press)
            lights = l; quit = q
            addSubview(l); addSubview(q)
        }
        guard let lights, let quit else { return }
        let ls = lights.frame.size, qs = quit.frame.size
        if controlsAreCompact {
            let x = bounds.width - 8 - qs.width
            quit.setFrameOrigin(NSPoint(x: x, y: (bounds.height - qs.height) / 2))
            lights.setFrameOrigin(NSPoint(x: x - 10 - ls.width, y: (bounds.height - ls.height) / 2))
        } else {
            let a = controlsAnchor
            lights.setFrameOrigin(NSPoint(x: a.minX + 8, y: a.maxY - 8 - ls.height))
            quit.setFrameOrigin(NSPoint(x: a.maxX - 8 - qs.width, y: a.maxY - 8 - qs.height))
        }
        lights.setHovering(forceGlyphs)
        lights.isHidden = false
        quit.isHidden = false
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
    private let titleIconView = NSImageView()
    private let markerLabel: NSTextField?
    private let showsThumbnails: Bool
    private var pictureFrame = NSRect.zero

    override var controlsAnchor: NSRect { pictureFrame }

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

        pictureFrame = picture
        thumbView.frame = picture
        thumbView.imageScaling = .scaleProportionallyUpOrDown
        thumbView.wantsLayer = true
        thumbView.layer?.cornerRadius = 6
        thumbView.layer?.masksToBounds = true
        addSubview(thumbView)

        // The app icon is the placeholder until a thumbnail lands, and the picture in App Icons.
        let side = layout == .thumbnails ? min(64, picture.height * 0.6) : min(52, picture.height)   // leaves room for the hover controls above
        iconView.frame = NSRect(x: picture.midX - side / 2, y: picture.midY - side / 2 - (layout == .thumbnails ? 0 : 6), width: side, height: side)
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
            markerLabel.frame = NSRect(x: layout == .thumbnails ? picture.minX + 4 : 6, y: layout == .thumbnails ? picture.minY + 4 : 3, width: s.width + 6, height: s.height)
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
        if layout == .thumbnails, icon != nil {
            // Small app icon beside the title; icon + text stay centred as a group and the text truncates first.
            let iconSide: CGFloat = 17, gap: CGFloat = 5
            let h = label.intrinsicContentSize.height
            let textW = min(label.intrinsicContentSize.width.rounded(.up) + 2, frame.width - 2 * inset - iconSide - gap)
            let groupW = iconSide + gap + textW
            let x0 = ((frame.width - groupW) / 2).rounded()
            let midY = 8 + labelH / 2
            titleIconView.frame = NSRect(x: x0, y: midY - iconSide / 2, width: iconSide, height: iconSide)
            titleIconView.image = icon
            titleIconView.imageScaling = .scaleProportionallyUpOrDown
            addSubview(titleIconView)
            label.alignment = .left
            label.frame = NSRect(x: x0 + iconSide + gap, y: midY - h / 2, width: textW, height: h)
        }
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

/// A row of round window-control buttons drawn like the macOS title-bar "traffic lights".
/// Glyphs show while the pointer is over the group (or always, for a single neutral button).
/// Works on the first click inside the non-activating panel.
final class ControlClusterView: NSView, NSViewToolTipOwner {
    enum Glyph { case close, minimize, fullScreen, power }
    struct Spec {
        let action: ItemAction
        let fill: NSColor
        let border: NSColor
        let glyph: Glyph
        let glyphColor: NSColor
        let tip: String
    }

    static let diameter: CGFloat = 13
    static let spacing: CGFloat = 8

    static let trafficLights: [Spec] = [
        Spec(action: .close, fill: rgb(0xFF5F57), border: rgb(0xE0443E), glyph: .close,
             glyphColor: rgb(0x4C0102, 0.75), tip: "Close window"),
        Spec(action: .minimize, fill: rgb(0xFEBC2E), border: rgb(0xDEA123), glyph: .minimize,
             glyphColor: rgb(0x985712, 0.8), tip: "Minimize or restore window"),
        Spec(action: .toggleFullScreen, fill: rgb(0x28C840), border: rgb(0x1AAB29), glyph: .fullScreen,
             glyphColor: rgb(0x0A5F0A, 0.8), tip: "Toggle full screen"),
    ]
    /// No native equivalent: neutral gray, kept apart from the traffic lights.
    static let quitSpec = Spec(action: .quitApp, fill: rgb(0x8E8E93), border: rgb(0x6C6C70), glyph: .power,
                               glyphColor: NSColor.white.withAlphaComponent(0.92), tip: "Quit app")

    private static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    private let specs: [Spec]
    private let glyphsOnHoverOnly: Bool
    private let onAction: (ItemAction) -> Void
    private var hovering = false
    private var pressed: Int?

    init(specs: [Spec], glyphsOnHoverOnly: Bool, onAction: @escaping (ItemAction) -> Void) {
        self.specs = specs
        self.glyphsOnHoverOnly = glyphsOnHoverOnly
        self.onAction = onAction
        let n = CGFloat(specs.count)
        super.init(frame: NSRect(x: 0, y: 0, width: n * Self.diameter + (n - 1) * Self.spacing, height: Self.diameter))
        for i in specs.indices { addToolTip(circle(i), owner: self, userData: UnsafeMutableRawPointer(bitPattern: i + 1)) }
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private func circle(_ i: Int) -> NSRect {
        NSRect(x: CGFloat(i) * (Self.diameter + Self.spacing), y: 0, width: Self.diameter, height: Self.diameter)
    }

    private func index(at point: NSPoint) -> Int? {
        specs.indices.first { circle($0).insetBy(dx: -Self.spacing / 2, dy: -3).contains(point) }
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        guard let raw = data.map({ Int(bitPattern: $0) }), raw >= 1, raw <= specs.count else { return "" }
        return specs[raw - 1].tip
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        for (i, spec) in specs.enumerated() {
            let rect = circle(i)
            let body = NSBezierPath(ovalIn: rect.insetBy(dx: 0.25, dy: 0.25))
            (pressed == i ? spec.fill.blended(withFraction: 0.25, of: .black) ?? spec.fill : spec.fill).setFill()
            body.fill()
            spec.border.setStroke()
            body.lineWidth = 0.5
            body.stroke()
            if hovering || !glyphsOnHoverOnly { drawGlyph(spec.glyph, in: rect, color: spec.glyphColor) }
        }
    }

    private func drawGlyph(_ glyph: Glyph, in rect: NSRect, color: NSColor) {
        let c = NSPoint(x: rect.midX, y: rect.midY)
        color.setStroke()
        color.setFill()
        let path = NSBezierPath()
        path.lineWidth = 1.25
        path.lineCapStyle = .round
        switch glyph {
        case .close:
            let r: CGFloat = 2.3
            path.move(to: NSPoint(x: c.x - r, y: c.y - r)); path.line(to: NSPoint(x: c.x + r, y: c.y + r))
            path.move(to: NSPoint(x: c.x - r, y: c.y + r)); path.line(to: NSPoint(x: c.x + r, y: c.y - r))
            path.stroke()
        case .minimize:
            path.move(to: NSPoint(x: c.x - 3, y: c.y)); path.line(to: NSPoint(x: c.x + 3, y: c.y))
            path.stroke()
        case .fullScreen:
            // Two triangles pointing at opposite corners, as in macOS.
            let t = NSBezierPath()
            t.move(to: NSPoint(x: c.x + 2.9, y: c.y + 2.9)); t.line(to: NSPoint(x: c.x - 0.5, y: c.y + 2.9))
            t.line(to: NSPoint(x: c.x + 2.9, y: c.y - 0.5)); t.close()
            t.move(to: NSPoint(x: c.x - 2.9, y: c.y - 2.9)); t.line(to: NSPoint(x: c.x + 0.5, y: c.y - 2.9))
            t.line(to: NSPoint(x: c.x - 2.9, y: c.y + 0.5)); t.close()
            t.fill()
        case .power:
            path.lineWidth = 1.2
            path.appendArc(withCenter: c, radius: 2.9, startAngle: 120, endAngle: 60, clockwise: false)
            path.move(to: NSPoint(x: c.x, y: c.y + 0.4)); path.line(to: NSPoint(x: c.x, y: c.y + 3.4))
            path.stroke()
        }
    }

    // MARK: Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    func setHovering(_ on: Bool) { hovering = on; needsDisplay = true }

    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        pressed = index(at: convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let hit = index(at: convert(event.locationInWindow, from: nil))
        let was = pressed
        pressed = nil
        needsDisplay = true
        if let hit, hit == was { onAction(specs[hit].action) }
    }

    override func viewDidHide() { hovering = false; pressed = nil }
}
