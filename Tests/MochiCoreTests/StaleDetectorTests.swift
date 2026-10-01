import Foundation
import Testing
@testable import MochiCore

@Suite("StaleDetector.reconcileLifecycle")
struct StaleDetectorReconciliationTests {
    private func session(
        id: String = "a1",
        status: AgentStatus,
        lastActivityAt: Date,
        discovery: DiscoveryKind = .instrumented,
        source: SessionSource = .genericCLI,
        finishedAt: Date? = nil
    ) -> AgentSession {
        AgentSession(
            id: id, provider: .claude, source: source, status: status, discovery: discovery,
            startedAt: lastActivityAt, lastActivityAt: lastActivityAt, finishedAt: finishedAt
        )
    }

    // MARK: - The actual reported bug: persisted "working" must not mean "working forever"

    @Test("a session that just reported in stays exactly as it was — this is the restart-while-genuinely-working case")
    func freshSessionIsUntouched() {
        let now = Date()
        var sessions = ["a1": session(status: .working, lastActivityAt: now)]
        StaleDetector.reconcileLifecycle(&sessions, now: now)
        #expect(sessions["a1"]?.status == .working)
    }

    @Test("a working session quiet past staleThreshold becomes stale — this is the reported bug, fixed")
    func quietWorkingSessionBecomesStale() {
        let now = Date()
        let quietSince = now.addingTimeInterval(-StaleDetector.staleThreshold - 60)
        var sessions = ["a1": session(status: .working, lastActivityAt: quietSince)]
        StaleDetector.reconcileLifecycle(&sessions, now: now)
        #expect(sessions["a1"]?.status == .stale)
    }

    @Test("a session quiet past offlineThreshold becomes offline directly — this is the restart-after-it-died case")
    func veryQuietSessionBecomesOffline() {
        let now = Date()
        let quietSince = now.addingTimeInterval(-StaleDetector.offlineThreshold - 60)
        var sessions = ["a1": session(status: .working, lastActivityAt: quietSince)]
        StaleDetector.reconcileLifecycle(&sessions, now: now)
        #expect(sessions["a1"]?.status == .offline)
    }

    @Test("an already-stale session escalates to offline once offlineThreshold passes")
    func staleEscalatesToOffline() {
        let now = Date()
        let quietSince = now.addingTimeInterval(-StaleDetector.offlineThreshold - 60)
        var sessions = ["a1": session(status: .stale, lastActivityAt: quietSince)]
        StaleDetector.reconcileLifecycle(&sessions, now: now)
        #expect(sessions["a1"]?.status == .offline)
    }

    @Test("needsPermission and waiting are also subject to staleness, not just working")
    func attentionAndWaitingCanGoStale() {
        let now = Date()
        let quietSince = now.addingTimeInterval(-StaleDetector.staleThreshold - 60)
        var sessions = [
            "a1": session(id: "a1", status: .needsPermission, lastActivityAt: quietSince),
            "a2": session(id: "a2", status: .waiting, lastActivityAt: quietSince)
        ]
        StaleDetector.reconcileLifecycle(&sessions, now: now)
        #expect(sessions["a1"]?.status == .stale)
        #expect(sessions["a2"]?.status == .stale)
    }

    // MARK: - Terminal states are never rewritten

    @Test("a completed session remains done regardless of how old it is")
    func completedSessionsStayCompleted() {
        let now = Date()
        let longAgo = now.addingTimeInterval(-StaleDetector.offlineThreshold * 10)
        var sessions = ["a1": session(status: .done, lastActivityAt: longAgo, finishedAt: longAgo)]
        StaleDetector.reconcileLifecycle(&sessions, now: now)
        #expect(sessions["a1"]?.status == .done)
    }

    @Test("an error session remains an error regardless of how old it is")
    func errorSessionsStayError() {
        let now = Date()
        let longAgo = now.addingTimeInterval(-StaleDetector.offlineThreshold * 10)
        var sessions = ["a1": session(status: .error, lastActivityAt: longAgo)]
        StaleDetector.reconcileLifecycle(&sessions, now: now)
        #expect(sessions["a1"]?.status == .error)
    }

    @Test("an already-offline session is left alone, not repeatedly reprocessed")
    func offlineSessionsAreLeftAlone() {
        let now = Date()
        let longAgo = now.addingTimeInterval(-StaleDetector.offlineThreshold * 10)
        var sessions = ["a1": session(status: .offline, lastActivityAt: longAgo)]
        StaleDetector.reconcileLifecycle(&sessions, now: now)
        #expect(sessions["a1"]?.status == .offline)
    }

    @Test("idle is not treated as awaiting evidence, so it doesn't become stale merely for being quiet")
    func idleDoesNotBecomeStale() {
        let now = Date()
        let quietSince = now.addingTimeInterval(-StaleDetector.staleThreshold - 60)
        var sessions = ["a1": session(status: .idle, lastActivityAt: quietSince)]
        StaleDetector.reconcileLifecycle(&sessions, now: now)
        #expect(sessions["a1"]?.status == .idle)
    }

    @Test("idle still eventually becomes offline if truly nothing confirms it for a very long time")
    func idleEventuallyGoesOffline() {
        let now = Date()
        let quietSince = now.addingTimeInterval(-StaleDetector.offlineThreshold - 60)
        var sessions = ["a1": session(status: .idle, lastActivityAt: quietSince)]
        StaleDetector.reconcileLifecycle(&sessions, now: now)
        #expect(sessions["a1"]?.status == .offline)
    }

    // MARK: - Passive discovery has its own, separate pruning (not this function's job)

    @Test("a detected-only session is never touched by lifecycle reconciliation")
    func detectedSessionsAreUntouched() {
        let now = Date()
        let longAgo = now.addingTimeInterval(-StaleDetector.offlineThreshold * 10)
        var sessions = ["a1": session(status: .idle, lastActivityAt: longAgo, discovery: .detected)]
        StaleDetector.reconcileLifecycle(&sessions, now: now)
        #expect(sessions["a1"]?.status == .idle)
        #expect(sessions["a1"] != nil)
    }

    // MARK: - Demo sessions: temporary by construction, not by status

    @Test("a fresh demo session is kept")
    func freshDemoSessionIsKept() {
        let now = Date()
        var sessions = ["a1": session(status: .working, lastActivityAt: now, source: .demo)]
        StaleDetector.reconcileLifecycle(&sessions, now: now)
        #expect(sessions["a1"] != nil)
    }

    @Test("a demo session past demoRetention is removed outright, regardless of status")
    func expiredDemoSessionIsRemoved() {
        let now = Date()
        let old = now.addingTimeInterval(-StaleDetector.demoRetention - 30)
        var sessions = [
            "working": session(id: "working", status: .working, lastActivityAt: old, source: .demo),
            "done": session(id: "done", status: .done, lastActivityAt: old, source: .demo, finishedAt: old)
        ]
        StaleDetector.reconcileLifecycle(&sessions, now: now)
        #expect(sessions.isEmpty)
    }

    @Test("expiring demo sessions never removes a real session that merely shares a quiet moment")
    func demoExpiryNeverTouchesRealSessions() {
        let now = Date()
        // Well past demoRetention (~2 min) but nowhere near staleThreshold (20 min) — isolates
        // "demo expiry fired" from "staleness also fired" so this test checks exactly one thing.
        let old = now.addingTimeInterval(-StaleDetector.demoRetention - 30)
        var sessions = [
            "demo-huginn": session(id: "demo-huginn", status: .working, lastActivityAt: old, source: .demo),
            "real-huginn": session(id: "real-huginn", status: .working, lastActivityAt: old, source: .genericCLI)
        ]
        StaleDetector.reconcileLifecycle(&sessions, now: now)
        #expect(sessions["demo-huginn"] == nil)
        // The real session with the same project-ish name survives, untouched — a project
        // genuinely named like a demo scenario is never at risk, by construction.
        #expect(sessions["real-huginn"]?.status == .working)
    }

    @Test("a legacy session with no recorded source (predates source tracking) is reconciled like any other non-demo session, never deleted")
    func unknownSourceIsReconciledNotDeleted() {
        let now = Date()
        let quietSince = now.addingTimeInterval(-StaleDetector.staleThreshold - 60)
        var sessions = ["a1": session(status: .working, lastActivityAt: quietSince, source: .unknown)]
        StaleDetector.reconcileLifecycle(&sessions, now: now)
        #expect(sessions["a1"] != nil)
        #expect(sessions["a1"]?.status == .stale)
    }

    // MARK: - Process liveness (unrelated to the threshold logic above)

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
