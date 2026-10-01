import Foundation
import Testing
@testable import MochiCore

@Suite("DemoCleanup")
struct DemoCleanupTests {
    @Test("removes a demo session's event files and leaves real sessions untouched")
    func removesOnlyDemoData() throws {
        let paths = makeTestPaths()
        let writer = EventWriter(paths: paths)

        var demoEvent = makeEvent(agentId: "demo-claude-huginn", status: "working")
        demoEvent.source = "demo"
        try writer.write(demoEvent)

        var realEvent = makeEvent(agentId: "real-claude-huginn", status: "working")
        realEvent.source = "genericCLI"
        try writer.write(realEvent)

        let result = DemoCleanup.removeAllDemoData(paths: paths)
        #expect(result.removedSessionCount == 1)
        #expect(result.removedFileCount == 1)

        let remaining = SessionProjection.replayAll(paths: paths)
        #expect(remaining.sessions["demo-claude-huginn"] == nil)
        #expect(remaining.sessions["real-claude-huginn"] != nil)
    }

    @Test("a mix of demo and real sessions across multiple events each removes only the demo ones")
    func mixedSessionsOnlyDemoRemoved() throws {
        let paths = makeTestPaths()
        let writer = EventWriter(paths: paths)
        let t0 = Date()

        for i in 0..<3 {
            var event = makeEvent(agentId: "demo-\(i)", status: "working", timestamp: t0.addingTimeInterval(Double(i)))
            event.source = "demo"
            try writer.write(event)
        }
        for i in 0..<2 {
            var event = makeEvent(agentId: "real-\(i)", status: "working", timestamp: t0.addingTimeInterval(Double(i) + 10))
            event.source = "openclaw"
            try writer.write(event)
        }

        let result = DemoCleanup.removeAllDemoData(paths: paths)
        #expect(result.removedSessionCount == 3)

        let remaining = SessionProjection.replayAll(paths: paths)
        #expect(remaining.sessions.count == 2)
        #expect(remaining.sessions.keys.allSatisfy { $0.hasPrefix("real-") })
    }

    @Test("cleanup on a store with no demo data removes nothing")
    func noDemoDataIsNoOp() throws {
        let paths = makeTestPaths()
        let writer = EventWriter(paths: paths)
        var event = makeEvent(agentId: "real-only", status: "working")
        event.source = "genericCLI"
        try writer.write(event)

        let result = DemoCleanup.removeAllDemoData(paths: paths)
        #expect(result.removedSessionCount == 0)
        #expect(result.removedFileCount == 0)

        let remaining = SessionProjection.replayAll(paths: paths)
        #expect(remaining.sessions["real-only"] != nil)
    }

    @Test("also cleans the app's persisted snapshot, not just the raw event files")
    func cleansSnapshotToo() throws {
        let paths = makeTestPaths()
        let store = PersistenceStore(paths: paths)
        let demoSession = AgentSession(id: "demo-x", provider: .claude, source: .demo, status: .working)
        let realSession = AgentSession(id: "real-x", provider: .claude, source: .genericCLI, status: .working)
        store.saveSessionSnapshot([demoSession, realSession])

        // No raw event files exist for either — cleanup must still consult the snapshot via
        // SessionProjection... actually SessionProjection doesn't read the snapshot, it
        // replays events. To be removed here, the demo session also needs an event on disk.
        var demoEvent = makeEvent(agentId: "demo-x", status: "working")
        demoEvent.source = "demo"
        try EventWriter(paths: paths).write(demoEvent)

        DemoCleanup.removeAllDemoData(paths: paths)

        let remainingSnapshot = store.loadSessionSnapshot()
        #expect(remainingSnapshot.contains { $0.id == "demo-x" } == false)
        #expect(remainingSnapshot.contains { $0.id == "real-x" } == true)
    }
}
