import AppKit
import ApplicationServices
import ScreenCaptureKit
import TabbyCore

/// Background-refreshed window cache. `currentWindows()` only reads memory (filter + MRU sort of
/// an in-memory array), so the Option+Tab path never waits on the OS.
///
/// Refresh sources: ScreenCaptureKit lists every window on every Space (including minimized and
/// hidden apps); Accessibility adds the minimized flag for current-Space apps. If ScreenCaptureKit
/// fails (no Screen Recording permission) the cache falls back to the public CoreGraphics list.
final class WindowInventory: WindowSource, @unchecked Sendable {
    private let lock = NSLock()
    private var windows: [WindowInfo] = []
    private var mru = MRUOrder()
    private var settings: Settings
    private var refreshing = false
    private var refreshAgain = false
    private var debounce: DispatchWorkItem?
    private var timer: Timer?
    private var observers: [pid_t: AXObserver] = [:]
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private let fallback = CoreGraphicsWindowSource()
    private let work = DispatchQueue(label: "tabby.inventory", qos: .userInitiated)

    init(settings: Settings) { self.settings = settings }

    // MARK: WindowSource

    func currentWindows() -> [WindowInfo] {
        lock.lock()
        defer { lock.unlock() }
        return mru.ordered(WindowInventoryRules.visible(windows, settings: settings))
    }

    func apply(_ settings: Settings) {
        lock.lock()
        self.settings = settings
        lock.unlock()
    }

    // MARK: Lifecycle (main thread)

    func start() {
        // Seed MRU from the current front-to-back z-order of on-screen windows.
        let seed = fallback.currentWindows().map(\.id)
        lock.lock()
        mru = MRUOrder(seed: seed)
        lock.unlock()

        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(appActivated(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        nc.addObserver(self, selector: #selector(appLaunched(_:)), name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        nc.addObserver(self, selector: #selector(appTerminated(_:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didHideApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification] {
            nc.addObserver(self, selector: #selector(requestRefresh), name: name, object: nil)
        }
        // Safety net for window events no notification covers (e.g. an app with no AX support).
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.requestRefresh() }
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular { observe(app.processIdentifier) }
        requestRefresh()
    }

    /// Records a focus change (our own commit, or an observed one) in MRU order.
    func noteFocused(_ id: UInt32) {
        lock.lock()
        mru.focused(id)
        lock.unlock()
        requestRefresh()
    }

    // MARK: Notifications

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        recordFocusedWindow(pid: app.processIdentifier)
        requestRefresh()
    }

    @objc private func appLaunched(_ note: Notification) {
        if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
           app.activationPolicy == .regular { observe(app.processIdentifier) }
        requestRefresh()
    }

    @objc private func appTerminated(_ note: Notification) {
        if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            stopObserving(app.processIdentifier)
        }
        requestRefresh()
    }

    fileprivate func recordFocusedWindow(pid: pid_t) {
        guard pid != ownPID else { return }
        work.async { [self] in
            if let id = AXWindows.focusedWindowID(pid: pid) { noteFocused(id) }
        }
    }

    // MARK: AX window events

    private func observe(_ pid: pid_t) {
        guard pid != ownPID, observers[pid] == nil else { return }
        var observer: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon else { return }
            let me = Unmanaged<WindowInventory>.fromOpaque(refcon).takeUnretainedValue()
            var pid: pid_t = 0
            AXUIElementGetPid(element, &pid)
            if (notification as String) == kAXFocusedWindowChangedNotification { me.recordFocusedWindow(pid: pid) }
            me.requestRefresh()
        }
        guard AXObserverCreate(pid, callback, &observer) == .success, let observer else { return }
        let app = AXWindows.application(pid)
        let me = Unmanaged.passUnretained(self).toOpaque()
        for n in [kAXFocusedWindowChangedNotification, kAXWindowCreatedNotification,
                  kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification,
                  kAXWindowDeminiaturizedNotification] {
            AXObserverAddNotification(observer, app, n as CFString, me)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }

    private func stopObserving(_ pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    // MARK: Refresh

    /// Coalesces bursts of events into one refresh. Safe from any thread.
    @objc func requestRefresh() {
        DispatchQueue.main.async { [self] in
            debounce?.cancel()
            let item = DispatchWorkItem { [weak self] in self?.refreshNow() }
            debounce = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
        }
    }

    private func refreshNow() {
        lock.lock()
        if refreshing { refreshAgain = true; lock.unlock(); return }
        refreshing = true
        lock.unlock()
        Task.detached { [self] in
            let list = await fetch()
            if store(list) { requestRefresh() }
        }
    }

    /// Returns true when another refresh was requested while this one ran.
    private func store(_ list: [WindowInfo]) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        windows = list
        mru.prune(keeping: Set(list.map(\.id)))
        refreshing = false
        let again = refreshAgain
        refreshAgain = false
        return again
    }

    private func fetch() async -> [WindowInfo] {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) else {
            // cfn: no Screen Recording permission means current-Space windows only; re-tried each refresh.
            return fallback.currentWindows()
        }
        var policy: [pid_t: NSRunningApplication?] = [:]
        var records: [WindowRecord] = []
        for w in content.windows {
            guard let owner = w.owningApplication else { continue }
            let pid = owner.processID
            let app = policy[pid] ?? NSRunningApplication(processIdentifier: pid)
            policy[pid] = app
            records.append(WindowRecord(
                id: w.windowID, pid: pid, appName: owner.applicationName,
                bundleID: owner.bundleIdentifier, title: w.title ?? "", bounds: w.frame,
                layer: w.windowLayer, isOnScreen: w.isOnScreen,
                ownerIsRegular: app?.activationPolicy == .regular, isAppHidden: app?.isHidden ?? false
            ))
        }
        // AX only for apps with an off-screen window: that is where "minimized" must be told apart.
        let pids = Set(records.filter { !$0.isOnScreen && $0.ownerIsRegular }.map(\.pid))
        let ax = await withCheckedContinuation { (c: CheckedContinuation<[Int32: [AXWindowRecord]], Never>) in
            work.async {
                var out: [Int32: [AXWindowRecord]] = [:]
                for pid in pids { out[pid] = AXWindows.records(pid: pid) }
                c.resume(returning: out)
            }
        }
        return WindowInventoryRules.merge(records, ax: ax, ownPID: ownPID)
    }
}
