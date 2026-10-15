import AppKit
import CoreGraphics
import TabbyCore

/// P1 window source: public CoreGraphics only, windows on the current Space, front to back.
/// P2 replaces this with a ScreenCaptureKit-backed source (all Spaces, minimized, hidden).
struct CoreGraphicsWindowSource: WindowSource {
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private static let minimumSide: CGFloat = 40

    func currentWindows() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        var regularApps: [pid_t: Bool] = [:]
        var result: [WindowInfo] = []
        for entry in list {
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  let id = entry[kCGWindowNumber as String] as? UInt32,
                  let pid = entry[kCGWindowOwnerPID as String] as? Int32,
                  pid != ownPID,
                  (entry[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.width >= Self.minimumSide, bounds.height >= Self.minimumSide
            else { continue }
            let isRegular = regularApps[pid] ?? {
                let v = NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular
                regularApps[pid] = v
                return v
            }()
            guard isRegular else { continue }
            result.append(WindowInfo(
                id: id,
                pid: pid,
                appName: entry[kCGWindowOwnerName as String] as? String ?? "",
                title: entry[kCGWindowName as String] as? String ?? "",
                bounds: bounds
            ))
        }
        return result
    }
}
