import AppKit
import CoreGraphics
import ScreenCaptureKit
import TabbyCore

/// Window thumbnails: captures with ScreenCaptureKit, keeps them in a byte-budgeted LRU cache.
///
/// Open path: `image(for:)` only reads memory. All captures are async, at most 4 at once, and
/// do nothing without Screen Recording permission (the panel then shows app icons).
/// Captures run only for on-screen windows; one that goes off-screen during the capture is
/// stored as untrusted and can never replace an image already cached.
final class ThumbnailStore: @unchecked Sendable {
    static let maxConcurrent = 4

    /// Called on the main queue after a new image lands.
    var onCaptured: ((UInt32) -> Void)?
    /// Finds the ScreenCaptureKit window for an id (the inventory keeps the latest list).
    var windowLookup: ((UInt32) -> SCWindow?)?

    private let lock = NSLock()
    private var cache = ThumbnailCache<CGImage>()
    private var queued: [UInt32] = []
    private var queuedSet = Set<UInt32>()
    private var running = Set<UInt32>()
    private var enabled = false
    private var size = ThumbnailSize.medium

    func apply(_ settings: Settings) {
        lock.lock()
        enabled = settings.layout == .thumbnails
        size = settings.thumbnailSize
        lock.unlock()
    }

    /// Memory read only; safe on the open path.
    func image(for id: UInt32) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        return cache.value(for: id)
    }

    /// Evicts images of windows that no longer exist.
    func prune(keeping live: Set<UInt32>) {
        lock.lock()
        cache.prune(keeping: live)
        lock.unlock()
    }

    /// Refreshes every window that is visible right now. Returns at once.
    func refreshOnScreen(_ windows: [WindowInfo]) {
        request(windows.filter { !$0.isMinimized && !$0.isOnOtherDesktop && !$0.isAppHidden }.map(\.id))
    }

    /// The window just lost focus and is still visible: the best moment for a fresh picture.
    func captureAfterFocusLoss(_ id: UInt32) { request([id]) }

    // MARK: Queue (max 4 concurrent)

    private func request(_ ids: [UInt32]) {
        guard Permissions.screenRecording else { return }
        lock.lock()
        guard enabled else { lock.unlock(); return }
        for id in ids where !queuedSet.contains(id) && !running.contains(id) {
            queued.append(id)
            queuedSet.insert(id)
        }
        lock.unlock()
        pump()
    }

    private func pump() {
        while true {
            lock.lock()
            guard running.count < Self.maxConcurrent, !queued.isEmpty else { lock.unlock(); return }
            let id = queued.removeFirst()
            queuedSet.remove(id)
            running.insert(id)
            let size = size
            lock.unlock()
            Task.detached(priority: .utility) { [self] in
                await capture(id, size: size)
                finish(id)
                pump()
            }
        }
    }

    // MARK: Capture

    private func capture(_ id: UInt32, size: ThumbnailSize) async {
        guard Self.isOnScreen(id), let window = windowLookup?(id) else { return }
        let scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
        let target = PanelGeometry.fit(window.frame.size.applying(.init(scaleX: scale, y: scale)),
                                       in: size.capturePixels(scale: scale))
        let config = SCStreamConfiguration()
        config.width = max(Int(target.width), 1)
        config.height = max(Int(target.height), 1)
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        // Errors (permission revoked, window gone) just mean no new image.
        guard let image = try? await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: config) else { return }
        let trusted = Self.isOnScreen(id)
        let result = put(image, trusted: trusted, for: id)
        if case .stored = result { DispatchQueue.main.async { [self] in onCaptured?(id) } }
    }

    // Sync helpers: NSLock must not be taken directly from async code.
    private func finish(_ id: UInt32) {
        lock.lock()
        running.remove(id)
        lock.unlock()
    }

    private func put(_ image: CGImage, trusted: Bool, for id: UInt32) -> ThumbnailCache<CGImage>.StoreResult {
        lock.lock()
        defer { lock.unlock() }
        return cache.store(image, bytes: ThumbnailCache<CGImage>.bytes(width: image.width, height: image.height),
                           trusted: trusted, for: id)
    }

    private static func isOnScreen(_ id: UInt32) -> Bool {
        let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(id)) as? [[String: Any]]
        return (info?.first?[kCGWindowIsOnscreen as String] as? Bool) ?? false
    }
}
