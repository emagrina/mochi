import Foundation
import Testing
@testable import MochiCore

@Suite("Concurrent writers")
struct ConcurrencyTests {
    @Test("many simultaneous writers never corrupt or clobber each other's event files")
    func concurrentEventWriters() async throws {
        let paths = makeTestPaths()
        let writer = EventWriter(paths: paths)
        let writerCount = 60

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<writerCount {
                group.addTask {
                    let event = makeEvent(agentId: "agent-\(i)", message: "message-\(i)")
                    _ = try? writer.write(event)
                }
            }
        }

        let files = try FileManager.default.contentsOfDirectory(at: paths.inbox, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        #expect(files.count == writerCount)

        var seenAgentIds = Set<String>()
        for file in files {
            let data = try Data(contentsOf: file)
            let event = try MochiEvent.decode(data) // throws if any file is truncated/corrupted
            seenAgentIds.insert(event.agentId)
        }
        #expect(seenAgentIds.count == writerCount)
    }

    @Test("AtomicFile.write never leaves a half-written destination visible to a reader")
    func atomicOverwriteIsAllOrNothing() async throws {
        let paths = makeTestPaths()
        let destination = paths.state.appendingPathComponent("shared.json")
        try FileManager.default.createDirectory(at: paths.state, withIntermediateDirectories: true)

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<30 {
                group.addTask {
                    // One single repeated character per writer (not "\(i)", which is
                    // multi-character for i >= 10 and would make this assertion meaningless).
                    let letter = Character(UnicodeScalar(UInt8(65 + i)))
                    let payload = Data(String(repeating: letter, count: 1000).utf8)
                    try? AtomicFile.write(payload, to: destination)
                }
            }
        }

        // Whatever ends up on disk must be one writer's complete payload, never a mix.
        let finalData = try Data(contentsOf: destination)
        let asString = String(decoding: finalData, as: UTF8.self)
        guard let firstChar = asString.first else {
            Issue.record("destination file is empty")
            return
        }
        #expect(asString.count == 1000)
        #expect(asString.allSatisfy { $0 == firstChar })
    }
}
