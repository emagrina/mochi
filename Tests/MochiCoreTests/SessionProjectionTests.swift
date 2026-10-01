import Foundation
import Testing
@testable import MochiCore

@Suite("SessionProjection (CLI replay path)")
struct SessionProjectionTests {
    @Test("replays events from processed/ and inbox/ into session state")
    func replaysAcrossBothDirectories() throws {
        let paths = makeTestPaths()
        let writer = EventWriter(paths: paths)
        try writer.write(makeEvent(event: .start, agentId: "a1"))
        try writer.write(makeEvent(event: .status, agentId: "a1", status: "testing", timestamp: Date().addingTimeInterval(1)))

        // Simulate the app having already ingested the first event into processed/.
        let inboxFiles = try FileManager.default.contentsOfDirectory(at: paths.inbox, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        try FileManager.default.createDirectory(at: paths.processed, withIntermediateDirectories: true)
        if let first = inboxFiles.first {
            try FileManager.default.moveItem(at: first, to: paths.processed.appendingPathComponent(first.lastPathComponent))
        }

        let result = SessionProjection.replayAll(paths: paths)
        #expect(result.sessions["a1"]?.status == .testing)
        #expect(result.malformedCount == 0)
    }

    @Test("a malformed event file is counted, not thrown, and doesn't block other sessions")
    func malformedFileIsSkipped() throws {
        let paths = makeTestPaths()
        let writer = EventWriter(paths: paths)
        try writer.write(makeEvent(agentId: "good"))
        try Data("not json at all".utf8).write(to: paths.inbox.appendingPathComponent("broken.json"))

        let result = SessionProjection.replayAll(paths: paths)
        #expect(result.sessions["good"] != nil)
        #expect(result.malformedCount == 1)
    }

    @Test("an empty inbox produces no sessions and no crash")
    func emptyInbox() {
        let paths = makeTestPaths()
        let result = SessionProjection.replayAll(paths: paths)
        #expect(result.sessions.isEmpty)
        #expect(result.malformedCount == 0)
    }
}
