import AppKit
import ApplicationServices
import CoreGraphics

/// Live permission state. Cheap to call; the app polls it because either grant can be revoked
/// at any time, not just during first run.
enum Permissions {
    static var accessibility: Bool { AXIsProcessTrusted() }
    static var screenRecording: Bool { CGPreflightScreenCaptureAccess() }

    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        openSettings(pane: "Privacy_Accessibility")
    }

    static func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
        openSettings(pane: "Privacy_ScreenCapture")
    }

    private static func openSettings(pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// First-run window showing the status of each permission with a button to grant it.
final class OnboardingWindowController: NSWindowController {
    private let accessibilityRow = PermissionRow(
        title: "Accessibility",
        detail: "Lets Tabby see Option+Tab and bring a window to the front.",
        action: Permissions.requestAccessibility
    )
    private let screenRow = PermissionRow(
        title: "Screen Recording",
        detail: "Needed for window thumbnails. Without it Tabby shows app icons instead.",
        action: Permissions.requestScreenRecording
    )

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 250),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Tabby"
        window.isReleasedWhenClosed = false
        super.init(window: window)

        let heading = NSTextField(wrappingLabelWithString: "Tabby needs two permissions. Nothing leaves this Mac: the app contains no network code.")
        heading.font = .systemFont(ofSize: 13)
        let stack = NSStackView(views: [heading, accessibilityRow, screenRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        window.contentView = stack
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func present() {
        refresh()
        window?.center()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func refresh() {
        accessibilityRow.granted = Permissions.accessibility
        screenRow.granted = Permissions.screenRecording
    }
}

private final class PermissionRow: NSStackView {
    private let status = NSTextField(labelWithString: "")
    private let button = NSButton(title: "Grant Access", target: nil, action: nil)
    private let handler: () -> Void

    var granted = false {
        didSet {
            status.stringValue = granted ? "Granted" : "Not granted"
            status.textColor = granted ? .systemGreen : .systemOrange
            button.isHidden = granted
        }
    }

    init(title: String, detail: String, action: @escaping () -> Void) {
        handler = action
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 4

        let name = NSTextField(labelWithString: title)
        name.font = .boldSystemFont(ofSize: 13)
        let explain = NSTextField(wrappingLabelWithString: detail)
        explain.font = .systemFont(ofSize: 12)
        explain.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: 12)
        button.target = self
        button.action = #selector(tapped)
        let line = NSStackView(views: [status, button])
        line.spacing = 12
        for v in [name, explain, line] { addArrangedSubview(v) }
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func tapped() { handler() }
}
