import AppKit
import TabbyCore

/// Live preview: an outline around the selected window's on-screen frame and a light dim over
/// the other screens. Click-through, below the switcher panel, and it never touches the real
/// window, so nothing needs restoring: hiding the overlay is the whole cleanup.
final class PreviewOverlay {
    private static let dimAlpha: CGFloat = 0.2
    private var windows: [NSWindow] = []

    /// `frame` is the selected window's global top-left frame, or nil for no preview.
    func show(frame: CGRect?) {
        guard let frame else { return hide() }
        let screens = NSScreen.screens
        guard let primary = screens.first else { return hide() }
        let target = PreviewRules.appKitRect(fromGlobal: frame, primaryScreenHeight: primary.frame.height)
        let outlined = PreviewRules.screenIndex(for: target, among: screens.map(\.frame))
        if windows.count != screens.count { rebuild(count: screens.count) }
        for (i, screen) in screens.enumerated() {
            let window = windows[i]
            window.setFrame(screen.frame, display: false)
            let view = window.contentView as? OverlayView
            if i == outlined {
                view?.configure(outline: target.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY), dim: false)
            } else {
                view?.configure(outline: nil, dim: true)
            }
            window.orderFrontRegardless()
        }
    }

    func hide() {
        windows.forEach { $0.orderOut(nil) }
    }

    private func rebuild(count: Int) {
        windows.forEach { $0.orderOut(nil) }
        windows = (0..<count).map { _ in
            let w = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = false
            w.ignoresMouseEvents = true
            w.isReleasedWhenClosed = false
            w.level = .statusBar
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
            w.contentView = OverlayView()
            return w
        }
    }

    private final class OverlayView: NSView {
        private var outline: NSRect?
        private var dim = false

        func configure(outline: NSRect?, dim: Bool) {
            self.outline = outline
            self.dim = dim
            needsDisplay = true
        }

        override func draw(_ dirtyRect: NSRect) {
            if dim {
                NSColor.black.withAlphaComponent(PreviewOverlay.dimAlpha).setFill()
                bounds.fill()
            }
            guard let outline else { return }
            let path = NSBezierPath(roundedRect: outline.insetBy(dx: -3, dy: -3), xRadius: 10, yRadius: 10)
            path.lineWidth = 4
            NSColor.controlAccentColor.setStroke()
            path.stroke()
        }
    }
}
