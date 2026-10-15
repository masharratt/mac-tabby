import AppKit
import ServiceManagement
import SwiftUI
import TabbyCore

// SwiftUI also exports a `Settings` type; pin ours.
typealias Settings = TabbyCore.Settings

/// Holds the live settings. Every change is saved and pushed to `onChange` so the switcher
/// picks it up without a relaunch.
final class SettingsModel: ObservableObject {
    @Published var settings: Settings {
        didSet {
            guard settings != oldValue else { return }
            SettingsStore.save(settings)
            onChange?(settings)
        }
    }
    var onChange: ((Settings) -> Void)?

    init(settings: Settings) { self.settings = settings }
}

/// Launch-at-login via SMAppService. Only offered from /Applications, because a registration
/// made from a build folder would point at a path that may later vanish.
enum LaunchAtLogin {
    static var isAvailable: Bool { Bundle.main.bundlePath.hasPrefix("/Applications/") }
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Returns the error text on failure.
    static func set(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

final class SettingsWindowController: NSWindowController {
    init(model: SettingsModel) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Tabby Settings"
        window.contentViewController = NSHostingController(rootView: SettingsView(model: model))
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?
    @State private var runningApps: [AppChoice] = []

    var body: some View {
        Form {
            Section("Layout") {
                Picker("Switcher layout", selection: $model.settings.layout) {
                    Text("Titles").tag(Layout.titles)
                }
                // cfn: Thumbnails and App Icons are listed as text, not picker rows, because the
                // Layout enum has no such cases until stage 3; add them to the picker then.
                Text("Thumbnails and App Icons: coming soon")
                    .font(.callout).foregroundStyle(.secondary)
                Picker("Thumbnail size", selection: $model.settings.thumbnailSize) {
                    ForEach(ThumbnailSize.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .help("Used by the thumbnails layout, coming soon.")
                Toggle("Live preview of the selected window", isOn: $model.settings.livePreview)
                    .help("Takes effect when live preview arrives.")
            }
            Section("Windows to show") {
                Toggle("Minimized windows", isOn: $model.settings.showMinimized)
                Toggle("Windows from other desktops", isOn: $model.settings.showOtherDesktops)
                Toggle("Windows of hidden apps", isOn: $model.settings.showHiddenApps)
            }
            Section("Hidden apps") {
                hiddenAppsList
            }
            Section("General") {
                Toggle("Launch at login", isOn: launchBinding).disabled(!LaunchAtLogin.isAvailable)
                if !LaunchAtLogin.isAvailable {
                    Text("Move Tabby to the Applications folder to turn this on.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if let launchError {
                    Text(launchError).font(.callout).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 560)
        .onAppear {
            launchAtLogin = LaunchAtLogin.isEnabled
            runningApps = AppChoice.running()
        }
    }

    private var launchBinding: Binding<Bool> {
        Binding(get: { launchAtLogin }, set: { on in
            launchError = LaunchAtLogin.set(on)
            launchAtLogin = LaunchAtLogin.isEnabled
        })
    }

    @ViewBuilder private var hiddenAppsList: some View {
        Text("Windows of these apps never appear in the switcher.")
            .font(.callout).foregroundStyle(.secondary)
        ForEach(model.settings.hiddenApps, id: \.self) { entry in
            HStack {
                Text(AppChoice.displayName(for: entry))
                Spacer()
                Button("Remove") { model.settings.unhideApp(entry) }
            }
        }
        Menu("Add running app\u{2026}") {
            let hidden = Set(model.settings.hiddenApps.map { $0.lowercased() })
            let choices = runningApps.filter { !hidden.contains($0.identifier.lowercased()) }
            if choices.isEmpty {
                Text("No other running apps")
            }
            ForEach(choices) { choice in
                Button(choice.name) { model.settings.hideApp(choice.identifier) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            runningApps = AppChoice.running()
        }
    }
}

/// A running app offered in the hidden-apps picker. `identifier` is what gets stored:
/// the bundle id when there is one, else the app name.
private struct AppChoice: Identifiable {
    let name: String
    let identifier: String
    var id: String { identifier }

    static func running() -> [AppChoice] {
        let own = ProcessInfo.processInfo.processIdentifier
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != own }
            .compactMap { app -> AppChoice? in
                guard let name = app.localizedName else { return nil }
                let id = app.bundleIdentifier ?? name
                return seen.insert(id.lowercased()).inserted ? AppChoice(name: name, identifier: id) : nil
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Friendly name for a stored entry; falls back to the raw entry for apps not installed.
    static func displayName(for entry: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return entry
    }
}
