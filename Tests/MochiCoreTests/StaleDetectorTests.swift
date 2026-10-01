import Foundation
import Testing
@testable import MochiCore

@Suite("StaleDetector")
struct StaleDetectorTests {
    @Test("a recently-active working session is not stale")
    func freshIsNotStale() {
        let session = AgentSession(id: "a1", provider: .claude, status: .working, startedAt: Date(), lastActivityAt: Date())
        #expect(!StaleDetector.isStale(session))
    }

    @Test("a working session quiet past the threshold is stale")
    func quietSessionIsStale() {
        let longAgo = Date().addingTimeInterval(-StaleDetector.staleThreshold - 60)
        let session = AgentSession(id: "a1", provider: .claude, status: .working, startedAt: longAgo, lastActivityAt: longAgo)
        #expect(StaleDetector.isStale(session))
    }

    @Test("a finished session is never stale, however long ago it finished")
    func finishedIsNeverStale() {
        let longAgo = Date().addingTimeInterval(-StaleDetector.staleThreshold - 60)
        let session = AgentSession(id: "a1", provider: .claude, status: .done, startedAt: longAgo, lastActivityAt: longAgo, finishedAt: longAgo)
        #expect(!StaleDetector.isStale(session))
    }

    @Test("an idle session is never flagged stale (idle is already the quiet state)")
    func idleIsNeverStale() {
        let longAgo = Date().addingTimeInterval(-StaleDetector.staleThreshold - 60)
        let session = AgentSession(id: "a1", provider: .claude, status: .idle, startedAt: longAgo, lastActivityAt: longAgo)
        #expect(!StaleDetector.isStale(session))
    }

    @Test("a process we just spawned and waited for is correctly reported as not alive")
    func processLivenessReflectsRealExit() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "exit 0"]
        try process.run()
        process.waitUntilExit()
        let pid = process.processIdentifier
        #expect(!StaleDetector.isProcessAlive(pid: pid))
    }

    @Test("the current process reports itself as alive")
    func currentProcessIsAlive() {
        #expect(StaleDetector.isProcessAlive(pid: ProcessInfo.processInfo.processIdentifier))
    }
}
