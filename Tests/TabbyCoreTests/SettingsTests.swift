import Foundation
import Testing
@testable import TabbyCore

@Suite struct SettingsTests {
    @Test func defaults() {
        let s = Settings()
        #expect(s.layout == .titles)
        #expect(s.showDelayMilliseconds == 100)
        #expect(s.hiddenApps.isEmpty)
        #expect(s.showMinimized)
        #expect(s.showOtherDesktops)
        #expect(s.livePreview)
    }

    @Test func roundTrips() throws {
        var s = Settings()
        s.showDelayMilliseconds = 150
        s.hiddenApps = ["com.apple.finder"]
        s.showMinimized = false
        let back = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(s))
        #expect(back == s)
    }

    @Test func emptyObjectDecodesToDefaults() throws {
        let s = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))
        #expect(s == Settings())
    }

    @Test func partialObjectKeepsDefaultsForMissingKeys() throws {
        let s = try JSONDecoder().decode(Settings.self, from: Data(#"{"showMinimized":false}"#.utf8))
        #expect(s.showMinimized == false)
        #expect(s.showDelayMilliseconds == 100)
    }

    @Test func unknownLayoutFallsBackToTitles() throws {
        let s = try JSONDecoder().decode(Settings.self, from: Data(#"{"layout":"hologram"}"#.utf8))
        #expect(s.layout == .titles)
    }

    @Test func showDelayIsClamped() throws {
        let s = try JSONDecoder().decode(Settings.self, from: Data(#"{"showDelayMilliseconds":-5}"#.utf8))
        #expect(s.showDelayMilliseconds == 0)
        let big = try JSONDecoder().decode(Settings.self, from: Data(#"{"showDelayMilliseconds":99999}"#.utf8))
        #expect(big.showDelayMilliseconds == Settings.maxShowDelayMilliseconds)
    }

    @Test func storeFallsBackToDefaultsOnGarbage() {
        let suite = UserDefaults(suiteName: "tabby-test-\(UUID().uuidString)")!
        suite.set(Data("not json".utf8), forKey: SettingsStore.key)
        #expect(SettingsStore.load(from: suite) == Settings())
    }

    @Test func storeSaveThenLoad() {
        let suite = UserDefaults(suiteName: "tabby-test-\(UUID().uuidString)")!
        var s = Settings()
        s.livePreview = false
        SettingsStore.save(s, to: suite)
        #expect(SettingsStore.load(from: suite) == s)
    }

    // MARK: stage 2B

    @Test func newFieldDefaults() {
        let s = Settings()
        #expect(s.thumbnailSize == .medium)
        #expect(s.showHiddenApps)
    }

    @Test func stage2ASavedDataStillDecodes() throws {
        // Exactly what stage 2A wrote: no thumbnailSize, no showHiddenApps.
        let old = #"{"layout":"titles","showDelayMilliseconds":150,"hiddenApps":["Mail"],"showMinimized":false,"showOtherDesktops":true,"livePreview":false}"#
        let s = try JSONDecoder().decode(Settings.self, from: Data(old.utf8))
        #expect(s.showDelayMilliseconds == 150)
        #expect(s.hiddenApps == ["Mail"])
        #expect(s.showMinimized == false)
        #expect(s.livePreview == false)
        #expect(s.thumbnailSize == .medium)
        #expect(s.showHiddenApps)
    }

    @Test func newFieldsRoundTrip() throws {
        var s = Settings()
        s.thumbnailSize = .large
        s.showHiddenApps = false
        let back = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(s))
        #expect(back == s)
    }

    @Test func unknownThumbnailSizeFallsBackToMedium() throws {
        let s = try JSONDecoder().decode(Settings.self, from: Data(#"{"thumbnailSize":"gigantic"}"#.utf8))
        #expect(s.thumbnailSize == .medium)
    }

    @Test func hideAppAddsOnceCaseInsensitively() {
        var s = Settings()
        s.hideApp("com.apple.Safari")
        s.hideApp("COM.APPLE.SAFARI")
        s.hideApp("  ")
        #expect(s.hiddenApps == ["com.apple.Safari"])
    }

    @Test func unhideAppRemovesCaseInsensitively() {
        var s = Settings()
        s.hiddenApps = ["Mail", "com.apple.Safari"]
        s.unhideApp("com.apple.safari")
        #expect(s.hiddenApps == ["Mail"])
        s.unhideApp("not-there")
        #expect(s.hiddenApps == ["Mail"])
    }
}
