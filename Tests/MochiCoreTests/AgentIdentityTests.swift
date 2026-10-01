import Foundation
import Testing
@testable import MochiCore

@Suite("AgentIdentity")
struct AgentIdentityTests {
    @Test("configured display name wins over everything else")
    func displayNameWins() {
        let identity = AgentIdentity(key: "openclaw:lead", displayName: "Chief of Staff", name: "lead", role: "Coordinator", provider: .openclaw)
        #expect(identity.title == "Chief of Staff")
    }

    @Test("falls back to name when no display name is known")
    func fallsBackToName() {
        let identity = AgentIdentity(key: "openclaw:lead", displayName: nil, name: "lead", role: "Coordinator", provider: .openclaw)
        #expect(identity.title == "lead")
    }

    @Test("falls back to role when neither display name nor name is known")
    func fallsBackToRole() {
        let identity = AgentIdentity(key: "x", displayName: nil, name: nil, role: "Coordinator", provider: .openclaw)
        #expect(identity.title == "Coordinator")
    }

    @Test("falls back to the provider name as an absolute last resort — never the raw session key")
    func fallsBackToProviderNotKey() {
        let identity = AgentIdentity(key: "openclaw:agent:lead:dashboard:abc123-some-uuid", provider: .openclaw)
        #expect(identity.title == "OpenClaw")
    }

    @Test("empty strings are treated as absent, not as a valid name")
    func blankStringsAreSkipped() {
        let identity = AgentIdentity(key: "x", displayName: "   ", name: "", role: nil, provider: .claude)
        #expect(identity.title == "Claude")
    }

    @Test("secondaryDescriptor surfaces the role when it's distinct from the title")
    func secondaryDescriptorShowsRole() {
        let identity = AgentIdentity(key: "x", displayName: "Atlas", role: "Backend specialist", provider: .claude)
        #expect(identity.secondaryDescriptor == "Backend specialist")
    }

    @Test("secondaryDescriptor falls back to the provider when there's no distinct role")
    func secondaryDescriptorFallsBackToProvider() {
        let identity = AgentIdentity(key: "openclaw:developer", displayName: "Developer", provider: .openclaw)
        #expect(identity.secondaryDescriptor == "OpenClaw")
    }

    @Test("secondaryDescriptor is nil when the title already is the provider name — nothing more to say")
    func secondaryDescriptorNilWhenRedundant() {
        let identity = AgentIdentity(key: "x", provider: .claude)
        #expect(identity.title == "Claude")
        #expect(identity.secondaryDescriptor == nil)
    }
}

@Suite("Agent identity in SessionReducer")
struct SessionReducerAgentIdentityTests {
    @Test("a session with no agentKey defaults its identity key to its own session id")
    func defaultsKeyToSessionId() {
        var sessions: [String: AgentSession] = [:]
        SessionReducer.apply(makeEvent(event: .start, agentId: "session-1"), to: &sessions)
        #expect(sessions["session-1"]?.agentIdentity.key == "session-1")
    }

    @Test("agentDisplayName becomes the session's primary title, not the provider")
    func agentDisplayNameBecomesTitle() {
        var sessions: [String: AgentSession] = [:]
        var event = makeEvent(event: .start, agentId: "session-1", provider: "openclaw")
        event.agentDisplayName = "Chief of Staff"
        SessionReducer.apply(event, to: &sessions)
        #expect(sessions["session-1"]?.displayName == "Chief of Staff")
        #expect(sessions["session-1"]?.provider == .openclaw)
    }

    @Test("without an agentDisplayName, the title falls back to the provider — old behavior preserved")
    func noDisplayNameFallsBackToProvider() {
        var sessions: [String: AgentSession] = [:]
        SessionReducer.apply(makeEvent(event: .start, agentId: "session-1", provider: "claude"), to: &sessions)
        #expect(sessions["session-1"]?.displayName == "Claude")
    }

    @Test("two different sessions sharing an agentKey carry the same resolved identity, proving they're the same agent")
    func sharedAgentKeyLinksTwoSessions() {
        var sessions: [String: AgentSession] = [:]
        var main = makeEvent(event: .start, agentId: "openclaw:agent:lead:main", provider: "openclaw")
        main.agentKey = "openclaw:lead"
        main.agentDisplayName = "Chief of Staff"
        SessionReducer.apply(main, to: &sessions)

        var dashboard = makeEvent(event: .start, agentId: "openclaw:agent:lead:dashboard:xyz", provider: "openclaw")
        dashboard.agentKey = "openclaw:lead"
        dashboard.agentDisplayName = "Chief of Staff"
        SessionReducer.apply(dashboard, to: &sessions)

        #expect(sessions.count == 2) // still two distinct, independently-trackable sessions...
        #expect(sessions["openclaw:agent:lead:main"]?.agentIdentity.key == sessions["openclaw:agent:lead:dashboard:xyz"]?.agentIdentity.key)
        #expect(sessions["openclaw:agent:lead:main"]?.displayName == "Chief of Staff")
        #expect(sessions["openclaw:agent:lead:dashboard:xyz"]?.displayName == "Chief of Staff") // ...but the same recognizable agent
    }

    @Test("agentDisplayName refreshes on later events, the same way provider already does")
    func displayNameRefreshesOnLaterEvents() {
        var sessions: [String: AgentSession] = [:]
        let t0 = Date()
        SessionReducer.apply(makeEvent(event: .start, agentId: "a1", provider: "openclaw", timestamp: t0), to: &sessions)
        #expect(sessions["a1"]?.displayName == "OpenClaw") // no identity known yet

        var update = makeEvent(event: .status, agentId: "a1", provider: "openclaw", status: "working", timestamp: t0.addingTimeInterval(1))
        update.agentDisplayName = "Developer"
        SessionReducer.apply(update, to: &sessions)
        #expect(sessions["a1"]?.displayName == "Developer")
    }
}
