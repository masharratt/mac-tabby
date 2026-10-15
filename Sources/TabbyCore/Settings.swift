import Foundation

/// How the switcher draws its windows. P1 ships only `.titles`; P3 adds app icons and thumbnails.
public enum Layout: String, Codable, Sendable {
    case titles
    // cfn: P3 adds `appIcons` and `thumbnails`; every consumer switch must then handle them.
}

/// Thumbnail size for the thumbnails layout (stage 3). Stored now, unused until then.
public enum ThumbnailSize: String, Codable, CaseIterable, Sendable {
    case small, medium, large
}

public struct Settings: Codable, Equatable, Sendable {
    public static let maxShowDelayMilliseconds = 1000

    public var layout: Layout = .titles
    public var showDelayMilliseconds = 100 { didSet { showDelayMilliseconds = Self.clamp(showDelayMilliseconds) } }
    public var hiddenApps: [String] = []
    public var showMinimized = true
    public var showOtherDesktops = true
    public var livePreview = true
    public var thumbnailSize: ThumbnailSize = .medium
    public var showHiddenApps = true

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        // Unknown layout strings fall back to the default rather than failing the whole load.
        layout = (try? c.decodeIfPresent(Layout.self, forKey: .layout)) ?? d.layout
        showDelayMilliseconds = Self.clamp(try c.decodeIfPresent(Int.self, forKey: .showDelayMilliseconds) ?? d.showDelayMilliseconds)
        hiddenApps = try c.decodeIfPresent([String].self, forKey: .hiddenApps) ?? d.hiddenApps
        showMinimized = try c.decodeIfPresent(Bool.self, forKey: .showMinimized) ?? d.showMinimized
        showOtherDesktops = try c.decodeIfPresent(Bool.self, forKey: .showOtherDesktops) ?? d.showOtherDesktops
        livePreview = try c.decodeIfPresent(Bool.self, forKey: .livePreview) ?? d.livePreview
        thumbnailSize = (try? c.decodeIfPresent(ThumbnailSize.self, forKey: .thumbnailSize)) ?? d.thumbnailSize
        showHiddenApps = try c.decodeIfPresent(Bool.self, forKey: .showHiddenApps) ?? d.showHiddenApps
    }

    /// Adds a bundle id or app name to the hidden list; blank and duplicate (case-insensitive) entries are ignored.
    public mutating func hideApp(_ identifier: String) {
        let id = identifier.trimmingCharacters(in: .whitespaces)
        guard !id.isEmpty, !hiddenApps.contains(where: { $0.caseInsensitiveCompare(id) == .orderedSame }) else { return }
        hiddenApps.append(id)
    }

    public mutating func unhideApp(_ identifier: String) {
        hiddenApps.removeAll { $0.caseInsensitiveCompare(identifier) == .orderedSame }
    }

    public var showDelay: TimeInterval { Double(showDelayMilliseconds) / 1000 }

    private static func clamp(_ ms: Int) -> Int { min(max(ms, 0), maxShowDelayMilliseconds) }
}

public enum SettingsStore {
    public static let key = "tabby.settings"

    public static func load(from defaults: UserDefaults = .standard) -> Settings {
        guard let data = defaults.data(forKey: key),
              let s = try? JSONDecoder().decode(Settings.self, from: data) else { return Settings() }
        return s
    }

    public static func save(_ settings: Settings, to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: key) }
    }
}
