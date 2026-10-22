import AppKit
import Carbon.HIToolbox
import TabbyCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settingsModel = SettingsModel(settings: SettingsStore.load())
    private lazy var inventory = WindowInventory(settings: settingsModel.settings)
    private lazy var engine = SwitcherEngine(source: inventory, settings: settingsModel.settings)
    private lazy var settingsWindow = SettingsWindowController(model: settingsModel)
    private let tap = KeyEventTap()
    private let panel = SwitcherPanel()
    private let thumbnails = ThumbnailStore()
    private let preview = PreviewOverlay()
    private let onboarding = OnboardingWindowController()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    private var permissionTimer: Timer?
    private var tickTimer: Timer?
    private var activity: NSObjectProtocol?
    private var closeOnboardingWhenTrusted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        PrivateAPI.resolve()
        buildMenu()
        wireEngine()
        wireThumbnails()
        settingsModel.onChange = { [inventory, engine, panel, thumbnails] s in
            inventory.apply(s)
            engine.apply(s)
            panel.apply(s)
            thumbnails.apply(s)
        }
        WindowFocuser.onFocused = { [inventory] id in inventory.noteFocused(id) }
        inventory.start()
        pollPermissions()
        if !Permissions.accessibility {
            closeOnboardingWhenTrusted = true
            onboarding.present()
        }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.pollPermissions()
        }
    }

    // MARK: Engine wiring

    private func wireEngine() {
        tap.handler = { [engine] type, event in engine.process(type, event) }
        tap.onReenabled = { [engine] in engine.reset() }
        engine.onArmed = { [weak self] in self?.startTicking() }
        engine.onEffect = { [weak self] effect, windows in self?.handle(effect, windows) }
    }

    private func wireThumbnails() {
        let s = settingsModel.settings
        panel.apply(s)
        thumbnails.apply(s)
        panel.imageProvider = { [thumbnails] in thumbnails.image(for: $0) }
        panel.controlsAvailable = { WindowControls.isAvailable($0) }
        panel.onClickItem = { [engine] in engine.itemClick($0) }
        panel.onAction = { [weak self] action, index in self?.perform(action, at: index) }
        thumbnails.windowLookup = { [inventory] in inventory.scWindow(id: $0) }
        thumbnails.onCaptured = { [panel] in panel.thumbnailUpdated($0) }
        inventory.onFocusLost = { [thumbnails] in thumbnails.captureAfterFocusLoss($0) }
        inventory.onWindowsChanged = { [thumbnails] in thumbnails.prune(keeping: $0) }
    }

    private func handle(_ effect: SwitcherEffect, _ windows: [WindowInfo]) {
        switch effect {
        case let .show(selection):
            // Cached images first; captures start after the panel is up and swap in as they land.
            panel.show(windows: windows, selection: selection)
            engine.setPanelFrame(panel.globalFrame)
            updatePreview(windows, selection)
            thumbnails.refreshOnScreen(windows)
        case let .selectionChanged(selection):
            panel.updateSelection(selection)
            updatePreview(windows, selection)
        case let .listChanged(selection):
            panel.reload(windows: windows, selection: selection)
            engine.setPanelFrame(panel.globalFrame)
            updatePreview(windows, selection)
        case let .commit(index):
            closeSwitcher()
            if windows.indices.contains(index) { WindowFocuser.focus(windows[index]) }
        case .cancel:
            closeSwitcher()
        }
    }

    private func closeSwitcher() {
        stopTicking()
        preview.hide()
        engine.setPanelFrame(nil)
        panel.hide()
    }

    /// Outline the selected window when live preview is on. The real window is never raised.
    private func updatePreview(_ windows: [WindowInfo], _ selection: Int) {
        guard settingsModel.settings.livePreview, windows.indices.contains(selection) else { return preview.hide() }
        preview.show(frame: PreviewRules.outlineFrame(for: windows[selection]))
    }

    // MARK: Hover controls

    private func perform(_ action: ItemAction, at index: Int) {
        let windows = engine.snapshot().windows
        guard windows.indices.contains(index) else { return }
        let w = windows[index]
        switch action {
        case .close:
            if WindowControls.close(w) { removeAndRefresh([w.id]) }
        case .quitApp:
            if WindowControls.quitApp(w) { removeAndRefresh(Set(windows.filter { $0.pid == w.pid }.map(\.id))) }
        case .minimize:
            guard let minimized = WindowControls.toggleMinimized(w) else { return }
            engine.updateWindow(id: w.id) { $0.isMinimized = minimized }
            let s = engine.snapshot()
            panel.reload(windows: s.windows, selection: s.selection)
            updatePreview(s.windows, s.selection)
        case .toggleFullScreen:
            _ = WindowControls.toggleFullScreen(w)
        }
    }

    /// The list shrinks in place now; the background inventory catches up shortly after.
    private func removeAndRefresh(_ ids: Set<UInt32>) {
        engine.removeWindows(ids: ids)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [inventory] in inventory.requestRefresh() }
    }

    /// While open: advance the show delay and catch a missed Option release by polling the
    /// real modifier state, because a dropped flagsChanged event would otherwise leave us stuck.
    private func startTicking() {
        guard tickTimer == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(options: .latencyCritical, reason: "Tabby switcher open")
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.025, repeats: true) { [weak self] _ in
            guard let self else { return }
            let held = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlternate)
            engine.tick(optionHeld: held)
            if engine.isIdle { stopTicking() }
        }
    }

    private func stopTicking() {
        tickTimer?.invalidate()
        tickTimer = nil
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }

    // MARK: Permissions

    private func pollPermissions() {
        let trusted = Permissions.accessibility
        if trusted, !tap.isRunning { _ = tap.start() }
        if !trusted, tap.isRunning {
            tap.stop()
            engine.reset()
            closeSwitcher()
        }
        onboarding.refresh()
        if trusted, closeOnboardingWhenTrusted {
            // Accessibility is all this version needs; the first-run window closes once granted.
            closeOnboardingWhenTrusted = false
            onboarding.window?.close()
        }
    }

    // MARK: Menu

    private func buildMenu() {
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "Tabby")
        let menu = NSMenu()
        menu.delegate = self
        let title = NSMenuItem(title: "Tabby", action: nil, keyEquivalent: "")
        title.isEnabled = false
        statusLine.isEnabled = false
        menu.addItem(title)
        menu.addItem(statusLine)
        menu.addItem(.separator())
        let perms = NSMenuItem(title: "Permissions\u{2026}", action: #selector(showPermissions), keyEquivalent: "")
        perms.target = self
        menu.addItem(perms)
        let prefs = NSMenuItem(title: "Settings\u{2026}", action: #selector(showSettings), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Tabby", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if !Permissions.accessibility {
            statusLine.title = "Needs Accessibility permission"
        } else if !tap.isRunning {
            statusLine.title = "Keyboard hook not running"
        } else if IsSecureEventInputEnabled() {
            statusLine.title = "Paused: secure input is on"
        } else if !PrivateAPI.missingSymbols.isEmpty {
            statusLine.title = "Active (basic focus: some system calls unavailable)"
        } else {
            statusLine.title = "Active: hold Option, press Tab"
        }
    }

    @objc private func showPermissions() { onboarding.present() }
    @objc private func showSettings() { settingsWindow.present() }
}
