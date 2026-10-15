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
}
