import Foundation
import Testing
@testable import MochiCore

@Suite("EventInbox")
struct EventInboxTests {
    @Test("drain yields events in timestamp order and moves them to processed/")
    func drainOrdersAndArchives() async throws {
        let paths = makeTestPaths()
        let writer = EventWriter(paths: paths)
        let t0 = Date()
        try writer.write(makeEvent(agentId: "a1", status: "starting", timestamp: t0))
        try writer.write(makeEvent(agentId: "a1", status: "working", timestamp: t0.addingTimeInterval(0.01)))
        try writer.write(makeEvent(agentId: "a1", status: "testing", timestamp: t0.addingTimeInterval(0.02)))

        let inbox = EventInbox(paths: paths)
        var received: [String] = []
        for await event in await inbox.events() {
            received.append(event.status ?? "")
            if received.count == 3 { break }
        }

        #expect(received == ["starting", "working", "testing"])

        let remainingInInbox = try FileManager.default.contentsOfDirectory(at: paths.inbox, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        #expect(remainingInInbox.isEmpty)
        let processed = try FileManager.default.contentsOfDirectory(at: paths.processed, includingPropertiesForKeys: nil)
        #expect(processed.count == 3)
    }

    @Test("a malformed event is quarantined, not delivered, and does not block the rest")
    func malformedEventIsQuarantined() async throws {
        let paths = makeTestPaths()
        let writer = EventWriter(paths: paths)
        try Data("garbage".utf8).write(to: paths.inbox.appendingPathComponent("0-garbage.json"))
        try writer.write(makeEvent(agentId: "good"))

        let inbox = EventInbox(paths: paths)
        var received: [MochiEvent] = []
        for await event in await inbox.events() {
            received.append(event)
            break
        }
        #expect(received.first?.agentId == "good")

        let quarantined = try FileManager.default.contentsOfDirectory(at: paths.quarantine, includingPropertiesForKeys: nil)
        #expect(quarantined.count == 1)
    }

    @Test("replaying a cold-started backlog processes events written before the inbox ever watched")
    func coldStartBacklog() async throws {
        let paths = makeTestPaths()
        let writer = EventWriter(paths: paths)
        for i in 0..<5 {
            try writer.write(makeEvent(agentId: "a\(i)", timestamp: Date().addingTimeInterval(Double(i) * 0.01)))
        }

        let inbox = EventInbox(paths: paths)
        var count = 0
        for await _ in await inbox.events() {
            count += 1
            if count == 5 { break }
        }
        #expect(count == 5)
    }
}
