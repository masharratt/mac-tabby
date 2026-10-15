import ApplicationServices
import CoreGraphics
import Foundation

/// The ONLY file that touches private symbols. Each is resolved with dlsym at launch; a missing
/// symbol leaves its function pointer nil and callers fall back to public APIs.
enum PrivateAPI {
    // _AXUIElementGetWindow(AXUIElement, &CGWindowID) -> AXError
    // Maps an Accessibility window element to its CGWindowID. No public API exposes this link,
    // and without it AX windows cannot be matched to ScreenCaptureKit window records.
    private typealias AXGetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    // _SLPSSetFrontProcessWithOptions(&psn, windowID, mode) -> CGError
    // Asks the window server to make one specific window of a process frontmost, switching
    // Spaces if needed. NSRunningApplication.activate and AXRaise only act on windows of the
    // current Space and cannot target a single window across desktops.
    private typealias SetFrontFn = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UInt32, UInt32) -> CGError

    // SLPSPostEventRecordTo(&psn, bytes) -> CGError
    // Posts a raw window-server event record to a process. Used to tell the target app that its
    // window became key; the public CGEvent post APIs cannot address a process by PSN with this
    // record type, and SetFront alone leaves the window drawn inactive.
    private typealias PostRecordFn = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError

    // GetProcessForPID(pid, &psn) -> OSStatus
    // Converts a pid to a ProcessSerialNumber, which the two SkyLight calls above still require.
    // The public replacement (NSRunningApplication) exposes no PSN. Deprecated, not removed.
    private typealias GetPSNFn = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

    private static var axGetWindow: AXGetWindowFn?
    private static var setFront: SetFrontFn?
    private static var postRecord: PostRecordFn?
    private static var getPSN: GetPSNFn?

    /// Call once at launch, before any other thread uses this type.
    static func resolve() {
        // SkyLight is not linked; load it explicitly. RTLD_DEFAULT covers the already-loaded frameworks.
        let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        let handles: [UnsafeMutableRawPointer?] = [skyLight, UnsafeMutableRawPointer(bitPattern: -2)] // -2 == RTLD_DEFAULT
        func lookup<T>(_ name: String, _ type: T.Type) -> T? {
            for h in handles {
                if let p = dlsym(h, name) { return unsafeBitCast(p, to: T.self) }
            }
            return nil
        }
        axGetWindow = lookup("_AXUIElementGetWindow", AXGetWindowFn.self)
        setFront = lookup("_SLPSSetFrontProcessWithOptions", SetFrontFn.self)
        postRecord = lookup("SLPSPostEventRecordTo", PostRecordFn.self)
        getPSN = lookup("GetProcessForPID", GetPSNFn.self)
    }

    static var canMapAXWindows: Bool { axGetWindow != nil }
    static var canFocusViaSkyLight: Bool { setFront != nil && postRecord != nil && getPSN != nil }

    /// Names of symbols that failed to resolve, for the menu status line.
    static var missingSymbols: [String] {
        var m: [String] = []
        if axGetWindow == nil { m.append("_AXUIElementGetWindow") }
        if setFront == nil { m.append("_SLPSSetFrontProcessWithOptions") }
        if postRecord == nil { m.append("SLPSPostEventRecordTo") }
        if getPSN == nil { m.append("GetProcessForPID") }
        return m
    }

    static func windowID(of element: AXUIElement) -> UInt32? {
        guard let axGetWindow else { return nil }
        var wid: CGWindowID = 0
        guard axGetWindow(element, &wid) == .success, wid != 0 else { return nil }
        return wid
    }

    /// Brings `windowID` of `pid` to the front, across Spaces. Returns false if unavailable or failed.
    static func bringToFront(pid: pid_t, windowID: UInt32) -> Bool {
        guard canFocusViaSkyLight, let setFront, let postRecord, let getPSN else { return false }
        var psn = ProcessSerialNumber()
        guard getPSN(pid, &psn) == 0 else { return false }
        guard setFront(&psn, windowID, 0x200) == .success else { return false }
        // Two records: key-window "down" then "up". Layout: 0xF8-byte record, length 0xF8 at
        // offset 4, phase at 8, marker 0x10 at 0x3A, window id little-endian at 0x3C, 0xFF fill
        // over 0x20..<0x30.
        for phase: UInt8 in [0x01, 0x02] {
            var bytes = [UInt8](repeating: 0, count: 0xF8)
            bytes[0x04] = 0xF8
            bytes[0x08] = phase
            bytes[0x3A] = 0x10
            withUnsafeBytes(of: windowID.littleEndian) { raw in
                for i in 0..<4 { bytes[0x3C + i] = raw[i] }
            }
            for i in 0x20..<0x30 { bytes[i] = 0xFF }
            _ = bytes.withUnsafeMutableBufferPointer { postRecord(&psn, $0.baseAddress!) }
        }
        return true
    }
}
