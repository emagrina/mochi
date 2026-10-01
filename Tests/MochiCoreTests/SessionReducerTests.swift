import Foundation
import Testing
@testable import MochiCore

@Suite("SessionReducer")
struct SessionReducerTests {
    @Test("start creates a new session with the right defaults")
    func startCreatesSession() {
        var sessions: [String: AgentSession] = [:]
        let event = makeEvent(event: .start, agentId: "a1", status: "starting")
        SessionReducer.apply(event, to: &sessions)
        let session = sessions["a1"]
        #expect(session?.status == .starting)
        #expect(session?.provider == .claude)
    }

    @Test("status updates move the session through states")
    func statusTransitions() {
        var sessions: [String: AgentSession] = [:]
        SessionReducer.apply(makeEvent(event: .start, agentId: "a1"), to: &sessions)
        SessionReducer.apply(makeEvent(event: .status, agentId: "a1", status: "thinking", timestamp: Date().addingTimeInterval(1)), to: &sessions)
        SessionReducer.apply(makeEvent(event: .status, agentId: "a1", status: "testing", timestamp: Date().addingTimeInterval(2)), to: &sessions)
        #expect(sessions["a1"]?.status == .testing)
    }

    @Test("attention sets needsPermission and a reason, then clears on the next normal status")
    func attentionThenResolved() {
        var sessions: [String: AgentSession] = [:]
        let t0 = Date()
        SessionReducer.apply(makeEvent(event: .start, agentId: "a1", timestamp: t0), to: &sessions)
        SessionReducer.apply(makeEvent(event: .attention, agentId: "a1", status: "needsPermission", message: "needs OK", attentionReason: "permission", timestamp: t0.addingTimeInterval(1)), to: &sessions)
        #expect(sessions["a1"]?.status == .needsPermission)
        #expect(sessions["a1"]?.attentionReason == .permission)
        #expect(sessions["a1"]?.attentionMessage == "needs OK")

        SessionReducer.apply(makeEvent(event: .status, agentId: "a1", status: "working", timestamp: t0.addingTimeInterval(2)), to: &sessions)
        #expect(sessions["a1"]?.status == .working)
        #expect(sessions["a1"]?.attentionReason == nil)
        #expect(sessions["a1"]?.attentionMessage == nil)
    }

    @Test("completed sets done, finishedAt, and carries the pull request")
    func completed() {
        var sessions: [String: AgentSession] = [:]
        SessionReducer.apply(makeEvent(event: .start, agentId: "a1"), to: &sessions)
        var done = makeEvent(event: .completed, agentId: "a1", status: "done", message: "finished", timestamp: Date().addingTimeInterval(1))
        done.pullRequest = PullRequestInfo(number: 7, url: "https://example.com/pr/7", title: "Fix thing")
        SessionReducer.apply(done, to: &sessions)
        #expect(sessions["a1"]?.status == .done)
        #expect(sessions["a1"]?.finishedAt != nil)
        #expect(sessions["a1"]?.pullRequest?.number == 7)
    }

    @Test("error sets the error status and message")
    func error() {
        var sessions: [String: AgentSession] = [:]
        SessionReducer.apply(makeEvent(event: .start, agentId: "a1"), to: &sessions)
        SessionReducer.apply(makeEvent(event: .error, agentId: "a1", status: "error", message: "boom", timestamp: Date().addingTimeInterval(1)), to: &sessions)
        #expect(sessions["a1"]?.status == .error)
        #expect(sessions["a1"]?.errorMessage == "boom")
    }

    @Test("an older out-of-order event cannot regress current state, but is still logged")
    func outOfOrderDoesNotRegressState() {
        var sessions: [String: AgentSession] = [:]
        let t0 = Date()
        SessionReducer.apply(makeEvent(event: .start, agentId: "a1", status: "starting", timestamp: t0), to: &sessions)
        SessionReducer.apply(makeEvent(event: .status, agentId: "a1", status: "done", timestamp: t0.addingTimeInterval(10)), to: &sessions)
        // This "thinking" event has an earlier timestamp than what we already applied —
        // simulating network/filesystem reordering — so it must not revert status to thinking.
        SessionReducer.apply(makeEvent(event: .status, agentId: "a1", status: "thinking", message: "late arrival", timestamp: t0.addingTimeInterval(5)), to: &sessions)

        #expect(sessions["a1"]?.status == .done)
        #expect(sessions["a1"]?.recentActivity.contains { $0.message == "late arrival" } == true)
    }

    @Test("an exact duplicate event does not produce a duplicate log line")
    func duplicateEventIsIdempotentInLog() {
        var sessions: [String: AgentSession] = [:]
        let t0 = Date()
        let event = makeEvent(event: .status, agentId: "a1", status: "working", message: "editing foo.swift", timestamp: t0)
        SessionReducer.apply(makeEvent(event: .start, agentId: "a1", timestamp: t0.addingTimeInterval(-1)), to: &sessions)
        SessionReducer.apply(event, to: &sessions)
        SessionReducer.apply(event, to: &sessions) // retried delivery of the exact same event
        let matches = sessions["a1"]?.recentActivity.filter { $0.message == "editing foo.swift" } ?? []
        #expect(matches.count == 1)
    }

    @Test("multiple simultaneous sessions are tracked independently")
    func multipleSessionsAreIndependent() {
        var sessions: [String: AgentSession] = [:]
        SessionReducer.apply(makeEvent(event: .start, agentId: "a1", provider: "claude", status: "working"), to: &sessions)
        SessionReducer.apply(makeEvent(event: .start, agentId: "a2", provider: "codex", status: "testing"), to: &sessions)
        SessionReducer.apply(makeEvent(event: .error, agentId: "a2", status: "error", message: "oops", timestamp: Date().addingTimeInterval(1)), to: &sessions)

        #expect(sessions.count == 2)
        #expect(sessions["a1"]?.status == .working)
        #expect(sessions["a2"]?.status == .error)
        #expect(sessions["a1"]?.errorMessage == nil)
    }

    @Test("history is capped at maxHistoryPerSession")
    func historyIsCapped() {
        var sessions: [String: AgentSession] = [:]
        let t0 = Date()
        SessionReducer.apply(makeEvent(event: .start, agentId: "a1", timestamp: t0), to: &sessions)
        for i in 0..<(SessionReducer.maxHistoryPerSession + 20) {
            SessionReducer.apply(makeEvent(event: .status, agentId: "a1", status: "working", message: "step \(i)", timestamp: t0.addingTimeInterval(Double(i + 1))), to: &sessions)
        }
        #expect(sessions["a1"]?.recentActivity.count == SessionReducer.maxHistoryPerSession)
        #expect(sessions["a1"]?.recentActivity.last?.message == "step \(SessionReducer.maxHistoryPerSession + 19)")
    }

    @Test("metadata flags a process-detected session as detected, not instrumented")
    func discoveryKindFromMetadata() {
        var sessions: [String: AgentSession] = [:]
        var event = makeEvent(event: .status, agentId: "detected:claude:123", status: "idle")
        event.metadata = ["mochi.discoveryKind": "detected"]
        SessionReducer.apply(event, to: &sessions)
        #expect(sessions["detected:claude:123"]?.discovery == .detected)
    }
}
