import CoreGraphics

/// Pure rules for the live-preview outline.
public enum PreviewRules {
    /// The on-screen frame to outline, in global top-left coordinates. Nil when the window is not
    /// visibly on screen (minimized, other desktop, hidden app) or has no usable frame.
    public static func outlineFrame(for window: WindowInfo) -> CGRect? {
        guard !window.isMinimized, !window.isOnOtherDesktop, !window.isAppHidden else { return nil }
        guard window.bounds.width > 0, window.bounds.height > 0 else { return nil }
        return window.bounds
    }

    /// Global top-left (CoreGraphics) rect to AppKit bottom-left rect, flipped on the primary screen.
    public static func appKitRect(fromGlobal rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Index of the screen frame (same coordinate space as `rect`) with the largest overlap.
    public static func screenIndex(for rect: CGRect, among screens: [CGRect]) -> Int? {
        var best: (index: Int, area: CGFloat)?
        for (i, s) in screens.enumerated() {
            let r = s.intersection(rect)
            guard !r.isNull else { continue }
            let area = r.width * r.height
            if area > 0, area > (best?.area ?? 0) { best = (i, area) }
        }
        return best?.index
    }
}
