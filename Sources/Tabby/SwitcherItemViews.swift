import AppKit
import TabbyCore

/// One window in the switcher. Subclasses draw a list row or a grid tile.
class SwitcherItemView: NSView {
    let windowID: UInt32
    private(set) var isSelectedItem = false

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

    var primaryTextColor: NSColor { isSelectedItem ? .alternateSelectedControlTextColor : .labelColor }
    var secondaryTextColor: NSColor { isSelectedItem ? .alternateSelectedControlTextColor : .secondaryLabelColor }
}

/// Titles layout: icon, "App - Title", optional right-aligned tag.
final class RowItemView: SwitcherItemView {
    private let label: NSTextField
    private let markerLabel: NSTextField?

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

    init(frame: NSRect, window: WindowInfo, layout: Layout, thumbnailSize: ThumbnailSize,
         marker: String?, icon: NSImage?, thumbnail: CGImage?) {
        showsThumbnails = layout == .thumbnails
        label = NSTextField(labelWithString: layout == .thumbnails ? window.displayTitle : window.appName)
        markerLabel = marker.map { NSTextField(labelWithString: $0) }
        super.init(frame: frame, windowID: window.id)

        let labelH: CGFloat = 18
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
