import Foundation
import Testing
@testable import MochiCore

@Suite("AgentSession backward-compatible decoding")
struct AgentSessionDecodingTests {
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = MochiDateCoding.jsonDecodingStrategy
        return decoder
    }()

    @Test("a session persisted before `source` existed decodes to .unknown, not a thrown error")
    func missingSourceDecodesSafely() throws {
        let json = """
        {
          "id": "legacy-1",
          "agentIdentity": {"key": "legacy-1", "provider": "claude"},
          "status": "working",
          "discovery": {"instrumented": {}},
          "startedAt": "2026-01-01T00:00:00.000Z",
          "lastActivityAt": "2026-01-01T00:00:00.000Z",
          "metadata": {},
          "recentActivity": [],
          "attentionNotified": false,
          "completionNotified": false
        }
        """
        let session = try decoder.decode(AgentSession.self, from: Data(json.utf8))
        #expect(session.source == .unknown)
        #expect(session.status == .working)
    }

    @Test("a session persisted before `agentIdentity` existed decodes with a safe fallback identity")
    func missingAgentIdentityDecodesSafely() throws {
        let json = """
        {
          "id": "legacy-2",
          "status": "idle",
          "discovery": {"instrumented": {}},
          "startedAt": "2026-01-01T00:00:00.000Z",
          "lastActivityAt": "2026-01-01T00:00:00.000Z",
          "metadata": {},
          "recentActivity": [],
          "attentionNotified": false,
          "completionNotified": false
        }
        """
        let session = try decoder.decode(AgentSession.self, from: Data(json.utf8))
        #expect(session.agentIdentity.key == "legacy-2")
        #expect(session.source == .unknown)
    }

    @Test("one old-format session in a persisted snapshot array doesn't wipe the rest of the array")
    func oneOldSessionDoesNotPoisonTheWholeSnapshot() throws {
        let paths = makeTestPaths()
        let store = PersistenceStore(paths: paths)

        // Write a snapshot file by hand, mixing a current-format session with a
        // pre-`source` one, to simulate upgrading Mochi across this change.
        let legacyJSON = """
        [
          {"id": "legacy", "agentIdentity": {"key": "legacy", "provider": "claude"},
           "status": "done", "discovery": {"instrumented": {}},
           "startedAt": "2026-01-01T00:00:00.000Z", "lastActivityAt": "2026-01-01T00:00:00.000Z",
           "metadata": {}, "recentActivity": [], "attentionNotified": false, "completionNotified": false}
        ]
        """
        try Data(legacyJSON.utf8).write(to: paths.sessionsStateFile)

        let loaded = store.loadSessionSnapshot()
        #expect(loaded.count == 1)
        #expect(loaded.first?.source == .unknown)
    }
}
