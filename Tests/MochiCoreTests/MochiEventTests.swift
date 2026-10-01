import Foundation
import Testing
@testable import MochiCore

@Suite("MochiEvent protocol")
struct MochiEventTests {
    @Test("round-trips through JSON with millisecond precision")
    func roundTrip() throws {
        let original = makeEvent(message: "hello")
        let data = try original.encoded()
        let decoded = try MochiEvent.decode(data)
        #expect(decoded.agentId == original.agentId)
        #expect(decoded.message == "hello")
        #expect(abs(decoded.timestamp.timeIntervalSince(original.timestamp)) < 0.001)
    }

    @Test("rejects malformed JSON instead of crashing")
    func malformedJSON() {
        let data = Data("{not valid".utf8)
        #expect(throws: (any Error).self) {
            try MochiEvent.decode(data)
        }
    }

    @Test("rejects an empty agentId")
    func emptyAgentId() {
        let event = makeEvent(agentId: "")
        #expect(throws: (any Error).self) {
            try event.validate()
        }
    }

    @Test("rejects a future protocol version")
    func futureVersion() {
        var event = makeEvent()
        event.version = 99
        #expect(throws: (any Error).self) {
            try event.validate()
        }
    }

    @Test("decodes an unknown future status into .custom instead of failing")
    func unknownStatus() {
        let status = AgentStatus(rawValue: "negotiating")
        #expect(status == .custom("negotiating"))
        #expect(status.friendlyLabel == "Negotiating")
    }

    @Test("decodes an event missing every optional field")
    func minimalEvent() throws {
        let json = """
        {"version":1,"event":"heartbeat","agentId":"a1","timestamp":"2026-01-01T00:00:00.000Z"}
        """
        let decoded = try MochiEvent.decode(Data(json.utf8))
        #expect(decoded.agentId == "a1")
        #expect(decoded.status == nil)
        #expect(decoded.message == nil)
    }

    @Test("tolerates and ignores unknown extra fields from a future protocol version")
    func forwardCompatibleExtraFields() throws {
        let json = """
        {"version":1,"event":"status","agentId":"a1","status":"working",
         "timestamp":"2026-01-01T00:00:00.000Z","tokensUsed":1234,"costUSD":0.05}
        """
        let decoded = try MochiEvent.decode(Data(json.utf8))
        #expect(decoded.agentId == "a1")
        #expect(decoded.status == "working")
    }

    @Test("accepts a legacy whole-second ISO8601 timestamp (no fractional seconds)")
    func legacyTimestampFormat() throws {
        let json = """
        {"version":1,"event":"status","agentId":"a1","status":"working","timestamp":"2026-01-01T00:00:00Z"}
        """
        let decoded = try MochiEvent.decode(Data(json.utf8))
        #expect(decoded.agentId == "a1")
    }
}
