import CoreGraphics
import Foundation

/// A window as the switcher sees it. Platform-agnostic so ordering and display logic stay testable.
public struct WindowInfo: Equatable, Sendable, Identifiable {
    public var id: UInt32          // CGWindowID
    public var pid: Int32
    public var appName: String
    public var title: String
    public var bounds: CGRect

    public init(id: UInt32, pid: Int32, appName: String, title: String, bounds: CGRect = .zero) {
        self.id = id
        self.pid = pid
        self.appName = appName
        self.title = title
        self.bounds = bounds
    }

    /// One line for the Titles layout: "App — Title", or just the app name when untitled.
    public var displayTitle: String {
        if title.isEmpty || title == appName { return appName }
        return "\(appName) \u{2014} \(title)"
    }
}

/// Where the switcher gets its windows. P1: public CoreGraphics, current Space only.
/// P2 adds a ScreenCaptureKit-backed source covering all Spaces, minimized and hidden windows.
public protocol WindowSource: Sendable {
    /// Front-to-back (P2: most recently used first).
    func currentWindows() -> [WindowInfo]
}
