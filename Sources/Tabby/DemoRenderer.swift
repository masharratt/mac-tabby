import AppKit
import TabbyCore

/// `Tabby --render-demo <dir>`: draws the real item views with made-up windows into PNGs for the
/// README. Offscreen only: no window list, no screen capture, no event tap, nothing from the user's Mac.
enum DemoRenderer {
    private struct Fake {
        var bundleID: String
        var app: String
        var title: String
        var style: Int
        var hue: CGFloat
    }

    private static let fakes: [Fake] = [
        Fake(bundleID: "com.apple.Safari", app: "Safari", title: "localhost:3000", style: 1, hue: 0.58),
        Fake(bundleID: "com.apple.Notes", app: "Notes", title: "Quarterly plan.md", style: 0, hue: 0.12),
        Fake(bundleID: "com.apple.finder", app: "Finder", title: "Documents", style: 2, hue: 0.60),
        Fake(bundleID: "com.apple.Terminal", app: "Terminal", title: "build \u{2014} zsh", style: 3, hue: 0.0),
        Fake(bundleID: "com.apple.iCal", app: "Calendar", title: "October", style: 4, hue: 0.0),
        Fake(bundleID: "com.apple.mail", app: "Mail", title: "Inbox", style: 0, hue: 0.58),
    ]
    private static let selected = 1
    private static let minimizedIndex = 3
    private static let otherDesktopIndex = 4

    static func run(outputDir: String) {
        let dir = URL(fileURLWithPath: outputDir, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let jobs: [(String, Layout, Bool)] = [
            ("tabby-thumbnails.png", .thumbnails, false),
            ("tabby-thumbnails-dark.png", .thumbnails, true),
            ("tabby-app-icons.png", .appIcons, false),
        ]
        for (name, layout, dark) in jobs {
            let image = render(layout: layout, dark: dark)
            guard let png = image.representation(using: .png, properties: [:]) else { continue }
            let url = dir.appendingPathComponent(name)
            do { try png.write(to: url); print("wrote \(url.path)") } catch { print("failed \(url.path): \(error)") }
        }
    }

    private static func render(layout: Layout, dark: Bool) -> NSBitmapImageRep {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        var rep: NSBitmapImageRep!
        appearance.performAsCurrentDrawingAppearance {
            let screen = CGSize(width: 1440, height: 900)
            let grid = PanelGeometry.grid(count: fakes.count, selected: selected, layout: layout,
                                          thumbnailSize: .medium, screen: screen, showWindowTitles: true)
            let margin: CGFloat = 56
            let size = CGSize(width: grid.panelSize.width + 2 * margin, height: grid.panelSize.height + 2 * margin)

            let root = BackdropView(frame: NSRect(origin: .zero, size: size), dark: dark)
            root.appearance = appearance
            let panel = NSView(frame: NSRect(x: margin, y: margin, width: grid.panelSize.width, height: grid.panelSize.height))
            panel.wantsLayer = true
            panel.layer?.cornerRadius = 16
            panel.layer?.backgroundColor = (dark ? NSColor(white: 0.12, alpha: 0.78) : NSColor(white: 0.97, alpha: 0.78)).cgColor
            panel.layer?.borderWidth = 1
            panel.layer?.borderColor = (dark ? NSColor(white: 1, alpha: 0.14) : NSColor(white: 0, alpha: 0.10)).cgColor
            panel.layer?.shadowColor = NSColor.black.cgColor
            panel.layer?.shadowOpacity = dark ? 0.5 : 0.28
            panel.layer?.shadowRadius = 24
            panel.layer?.shadowOffset = CGSize(width: 0, height: -8)
            root.addSubview(panel)

            for (index, fake) in fakes.enumerated() {
                guard let slot = grid.slot(of: index) else { continue }
                let o = grid.origin(row: slot.row, column: slot.column)
                let frame = NSRect(x: o.x, y: grid.panelSize.height - o.y - grid.cellSize.height,
                                   width: grid.cellSize.width, height: grid.cellSize.height)
                var info = WindowInfo(id: UInt32(index + 1), pid: 0, appName: fake.app, title: fake.title)
                info.isMinimized = index == minimizedIndex
                info.isOnOtherDesktop = index == otherDesktopIndex
                let marker = info.isMinimized ? "Minimized" : (info.isOnOtherDesktop ? "Other desktop" : nil)
                let thumb = layout == .thumbnails ? thumbnail(fake, size: ThumbnailSize.medium.box, dark: dark) : nil
                let view = TileItemView(frame: frame, window: info, layout: layout, thumbnailSize: .medium,
                                        showWindowTitles: true, marker: marker, icon: icon(fake.bundleID), thumbnail: thumb)
                view.setSelected(index == selected)
                panel.addSubview(view)
            }

            rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            rep.size = size
            root.cacheDisplay(in: root.bounds, to: rep)
        }
        return rep
    }

    private static func icon(_ bundleID: String) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    // MARK: Synthetic thumbnails

    /// A made-up window: title bar with traffic lights and a few coloured blocks. Rendered at 2x.
    private static func thumbnail(_ fake: Fake, size: CGSize, dark: Bool) -> CGImage? {
        let scale: CGFloat = 2
        let w = Int(size.width * scale), h = Int(size.height * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        let W = size.width, H = size.height
        let terminal = fake.style == 3
        let body: CGColor = terminal ? NSColor(white: 0.1, alpha: 1).cgColor
            : (dark ? NSColor(white: 0.17, alpha: 1).cgColor : NSColor(white: 0.985, alpha: 1).cgColor)
        let bar: CGColor = terminal ? NSColor(white: 0.2, alpha: 1).cgColor
            : (dark ? NSColor(white: 0.25, alpha: 1).cgColor : NSColor(white: 0.90, alpha: 1).cgColor)
        let accent = NSColor(hue: fake.hue, saturation: 0.55, brightness: dark ? 0.85 : 0.9, alpha: 1).cgColor
        let soft = NSColor(hue: fake.hue, saturation: 0.18, brightness: dark ? 0.35 : 0.95, alpha: 1).cgColor
        let line: CGColor = dark ? NSColor(white: 1, alpha: 0.22).cgColor : NSColor(white: 0, alpha: 0.14).cgColor

        func rect(_ x: CGFloat, _ yTop: CGFloat, _ rw: CGFloat, _ rh: CGFloat, _ color: CGColor, r: CGFloat = 3) {
            ctx.setFillColor(color)
            ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: H - yTop - rh, width: rw, height: rh),
                               cornerWidth: r, cornerHeight: r, transform: nil))
            ctx.fillPath()
        }

        ctx.setFillColor(body); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        let barH: CGFloat = 20
        ctx.setFillColor(bar); ctx.fill(CGRect(x: 0, y: H - barH, width: W, height: barH))
        for (i, c) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
            ctx.setFillColor(c.cgColor)
            ctx.fillEllipse(in: CGRect(x: 8 + CGFloat(i) * 12, y: H - barH / 2 - 4, width: 8, height: 8))
        }
        rect(W / 2 - 34, 7, 68, 6, line, r: 3)

        let top = barH + 10
        switch fake.style {
        case 0: // document: heading plus text lines
            rect(16, top, 90, 9, accent, r: 4)
            for i in 0..<7 { rect(16, top + 20 + CGFloat(i) * 12, i % 3 == 2 ? 110 : W - 32 - CGFloat(i % 2) * 24, 5, line) }
        case 1: // web page: hero band, cards
            rect(0, barH, W, 54, soft, r: 0)
            rect(18, barH + 14, 110, 10, accent, r: 4)
            rect(18, barH + 32, 160, 5, line)
            for i in 0..<3 { rect(18 + CGFloat(i) * 62, barH + 66, 54, 40, i == 1 ? accent : soft, r: 5) }
        case 2: // file browser: sidebar and tiles
            rect(0, barH, 52, H - barH, soft, r: 0)
            for i in 0..<5 { rect(10, top + CGFloat(i) * 15, 32, 5, line) }
            for r in 0..<2 { for c in 0..<4 { rect(66 + CGFloat(c) * 34, top + CGFloat(r) * 40, 26, 26, c == 1 && r == 0 ? accent : soft, r: 5) } }
        case 3: // terminal: green prompt lines
            for i in 0..<7 {
                rect(14, top + CGFloat(i) * 13, 8, 5, NSColor.systemGreen.cgColor, r: 2)
                rect(28, top + CGFloat(i) * 13, 40 + CGFloat((i * 37) % 90), 5, NSColor(white: 1, alpha: 0.5).cgColor)
            }
        default: // calendar: grid of days
            for r in 0..<4 { for c in 0..<7 {
                let on = r == 1 && c == 3
                rect(14 + CGFloat(c) * 28, top + 4 + CGFloat(r) * 24, 22, 18, on ? NSColor.systemRed.cgColor : soft, r: 4)
            } }
        }
        return ctx.makeImage()
    }
}

/// Soft desktop-like gradient behind the panel.
private final class BackdropView: NSView {
    let dark: Bool
    init(frame: NSRect, dark: Bool) { self.dark = dark; super.init(frame: frame) }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func draw(_ dirtyRect: NSRect) {
        let colors: [NSColor] = dark
            ? [NSColor(red: 0.10, green: 0.12, blue: 0.24, alpha: 1), NSColor(red: 0.30, green: 0.16, blue: 0.38, alpha: 1), NSColor(red: 0.12, green: 0.28, blue: 0.40, alpha: 1)]
            : [NSColor(red: 0.62, green: 0.74, blue: 0.95, alpha: 1), NSColor(red: 0.85, green: 0.72, blue: 0.93, alpha: 1), NSColor(red: 0.98, green: 0.84, blue: 0.78, alpha: 1)]
        NSGradient(colors: colors)?.draw(in: bounds, angle: -35)
        // Two blurred-looking glows for depth.
        for (cx, cy, r, c) in [(0.2, 0.8, 0.5, NSColor.white.withAlphaComponent(dark ? 0.08 : 0.25)),
                               (0.85, 0.2, 0.55, NSColor.systemTeal.withAlphaComponent(dark ? 0.15 : 0.18))] {
            let radius = bounds.width * r
            NSGradient(colors: [c, c.withAlphaComponent(0)])?
                .draw(fromCenter: NSPoint(x: bounds.width * cx, y: bounds.height * cy), radius: 0,
                      toCenter: NSPoint(x: bounds.width * cx, y: bounds.height * cy), radius: radius, options: [])
        }
    }
}
