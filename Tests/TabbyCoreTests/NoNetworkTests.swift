import Foundation
import Testing
@testable import TabbyCore

/// Hard rule: Tabby contains zero network code. This scans every source file under Sources/.
@Suite struct NoNetworkTests {
    static let banned = [
        "URLSession", "URLRequest", "NSURLConnection", "NSURLSession", "URLProtocol",
        "NWConnection", "NWListener", "NWBrowser", "NWPathMonitor", "NWEndpoint",
        "import Network", "CFSocket", "CFStreamCreatePairWithSocket", "CFHTTP", "CFNetwork",
        "getaddrinfo", "gethostbyname", "NSNetService", "NetService", "MultipeerConnectivity",
        "WKWebView", "WebKit", "Sparkle", "SCNetworkReachability", "NSStream",
        "socket(", "connect(", "bind(", "sendto(", "SOCK_STREAM", "SOCK_DGRAM",
    ]

    static var sourcesDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
    }

    static func swiftFiles(in dir: URL) -> [URL] {
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return e.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    static func hits(in text: String) -> [String] {
        banned.filter { text.contains($0) }
    }

    @Test func scannerExaminedFiles() {
        let files = Self.swiftFiles(in: Self.sourcesDir)
        #expect(files.count >= 2, "scan examined \(files.count) files under \(Self.sourcesDir.path); certifying nothing")
    }

    @Test func scannerCatchesBannedNames() {
        #expect(Self.hits(in: "let s = URLSession.shared") == ["URLSession"])
        #expect(Self.hits(in: "import Network").contains("import Network"))
        #expect(Self.hits(in: "let x = 1").isEmpty)
    }

    @Test func sourcesContainNoNetworkAPIs() throws {
        var report: [String] = []
        for file in Self.swiftFiles(in: Self.sourcesDir) {
            let text = try String(contentsOf: file, encoding: .utf8)
            let h = Self.hits(in: text)
            if !h.isEmpty { report.append("\(file.lastPathComponent): \(h)") }
        }
        #expect(report.isEmpty, "network API names found: \(report)")
    }
}
