import Foundation
import Testing
@testable import MochiCore

@Suite("SessionSource")
struct SessionSourceTests {
    @Test("every known source round-trips through its raw value")
    func roundTrips() {
        let all: [SessionSource] = [.openClaw, .claudeCode, .codex, .genericCLI, .demo, .passiveDiscovery, .unknown]
        for source in all {
            #expect(SessionSource(rawValue: source.rawValue) == source)
        }
    }

    @Test("an unrecognized raw value folds to unknown, never crashes")
    func unrecognizedFoldsToUnknown() {
        #expect(SessionSource(rawValue: "something-from-the-future") == .unknown)
    }

    @Test("a missing source field decodes to unknown, not a decode failure")
    func missingSourceDecodesToUnknown() throws {
        let json = """
        {"version":1,"event":"status","agentId":"a1","status":"working","timestamp":"2026-01-01T00:00:00.000Z"}
        """
        let event = try MochiEvent.decode(Data(json.utf8))
        #expect(event.source == nil)

        var sessions: [String: AgentSession] = [:]
        SessionReducer.apply(event, to: &sessions)
        #expect(sessions["a1"]?.source == .unknown)
    }

    @Test("only OpenClaw is currently reconcilable — everything else is honestly not")
    func onlyOpenClawIsReconcilable() {
        #expect(SessionSource.openClaw.isReconcilable)
        #expect(!SessionSource.claudeCode.isReconcilable)
        #expect(!SessionSource.codex.isReconcilable)
        #expect(!SessionSource.genericCLI.isReconcilable)
        #expect(!SessionSource.demo.isReconcilable)
        #expect(!SessionSource.passiveDiscovery.isReconcilable)
        #expect(!SessionSource.unknown.isReconcilable)
    }
}

@Suite("Source propagation through SessionReducer")
struct SessionReducerSourceTests {
    @Test("a session records the source of the event that created it")
    func sourceIsCapturedOnCreation() {
        var sessions: [String: AgentSession] = [:]
        var event = makeEvent(event: .start, agentId: "a1")
        event.source = "openclaw"
        SessionReducer.apply(event, to: &sessions)
        #expect(sessions["a1"]?.source == .openClaw)
    }

    @Test("source is never overwritten once known, even if a later event claims something else")
    func sourceIsNotOverwrittenOnceKnown() {
        var sessions: [String: AgentSession] = [:]
        var first = makeEvent(event: .start, agentId: "a1", timestamp: Date())
        first.source = "demo"
        SessionReducer.apply(first, to: &sessions)

        var second = makeEvent(event: .status, agentId: "a1", status: "working", timestamp: Date().addingTimeInterval(1))
        second.source = "genericCLI"
        SessionReducer.apply(second, to: &sessions)

        #expect(sessions["a1"]?.source == .demo)
    }

    @Test("a session with no source at all on any event defaults to unknown, never genericCLI")
    func trulyUntaggedSessionIsUnknown() {
        var sessions: [String: AgentSession] = [:]
        SessionReducer.apply(makeEvent(event: .start, agentId: "a1"), to: &sessions)
        #expect(sessions["a1"]?.source == .unknown)
    }

    @Test("an unknown source can still be upgraded once a later event finally supplies one")
    func unknownSourceCanBeUpgraded() {
        var sessions: [String: AgentSession] = [:]
        SessionReducer.apply(makeEvent(event: .start, agentId: "a1", timestamp: Date()), to: &sessions)
        #expect(sessions["a1"]?.source == .unknown)

        var later = makeEvent(event: .status, agentId: "a1", status: "working", timestamp: Date().addingTimeInterval(1))
        later.source = "openclaw"
        SessionReducer.apply(later, to: &sessions)
        #expect(sessions["a1"]?.source == .openClaw)
    }
}
