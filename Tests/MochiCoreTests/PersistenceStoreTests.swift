import Foundation
import Testing
@testable import MochiCore

@Suite("PersistenceStore")
struct PersistenceStoreTests {
    @Test("loading settings with no file on disk returns defaults")
    func missingSettingsFileReturnsDefaults() {
        let store = PersistenceStore(paths: makeTestPaths())
        #expect(store.loadSettings() == MochiSettings.default)
    }

    @Test("settings round-trip through save/load")
    func settingsRoundTrip() {
        let store = PersistenceStore(paths: makeTestPaths())
        var settings = MochiSettings.default
        settings.notifyOnCompleted = false
        settings.keepCompletedVisibleMinutes = 42
        settings.appearance = .dark
        store.save(settings)
        let loaded = store.loadSettings()
        #expect(loaded == settings)
    }

    @Test("settings decode with missing keys fall back to defaults (old file, new app)")
    func partialSettingsFileUsesDefaults() throws {
        let paths = makeTestPaths()
        let partialJSON = Data(#"{"notifyOnCompleted": false}"#.utf8)
        try partialJSON.write(to: paths.settingsFile)
        let store = PersistenceStore(paths: paths)
        let loaded = store.loadSettings()
        #expect(loaded.notifyOnCompleted == false)
        #expect(loaded.keepCompletedVisibleMinutes == MochiSettings.default.keepCompletedVisibleMinutes)
    }

    @Test("settings decode tolerates unknown extra keys (new file, old app)")
    func extraKeysDoNotBreakDecoding() throws {
        let paths = makeTestPaths()
        let json = Data(#"{"notifyOnCompleted": true, "somethingFromTheFuture": 123}"#.utf8)
        try json.write(to: paths.settingsFile)
        let store = PersistenceStore(paths: paths)
        #expect(store.loadSettings().notifyOnCompleted == true)
    }

    @Test("session snapshot round-trips, including dates and attention flags")
    func sessionSnapshotRoundTrip() {
        let store = PersistenceStore(paths: makeTestPaths())
        let session = AgentSession(
            id: "a1", provider: .codex, status: .needsPermission,
            startedAt: Date(), lastActivityAt: Date(),
            attentionReason: .permission, attentionMessage: "needs OK",
            attentionNotified: true
        )
        store.saveSessionSnapshot([session])
        let loaded = store.loadSessionSnapshot()
        #expect(loaded.count == 1)
        #expect(loaded.first?.id == "a1")
        #expect(loaded.first?.attentionNotified == true)
        #expect(loaded.first?.attentionReason == .permission)
    }

    @Test("missing session snapshot file returns an empty array, not a crash")
    func missingSnapshotReturnsEmpty() {
        let store = PersistenceStore(paths: makeTestPaths())
        #expect(store.loadSessionSnapshot().isEmpty)
    }
}
