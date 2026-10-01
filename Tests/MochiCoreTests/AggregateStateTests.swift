import Foundation
import Testing
@testable import MochiCore

@Suite("AggregateState")
struct AggregateStateTests {
    private func session(_ status: AgentStatus) -> AgentSession {
        AgentSession(id: UUID().uuidString, provider: .claude, status: status, startedAt: Date(), lastActivityAt: Date())
    }

    @Test("needing attention outranks everything else, even errors")
    func attentionOutranksError() {
        let aggregate = AggregateState(sessions: [session(.needsPermission), session(.error), session(.working)])
        #expect(aggregate.headline == .needsAttention(1))
    }

    @Test("errors outrank active work when nothing needs attention")
    func errorOutranksActive() {
        let aggregate = AggregateState(sessions: [session(.error), session(.working)])
        #expect(aggregate.headline == .error(1))
    }

    @Test("active work outranks waiting")
    func activeOutranksWaiting() {
        let aggregate = AggregateState(sessions: [session(.working), session(.waiting)])
        #expect(aggregate.headline == .active(1))
    }

    @Test("all sessions done reports allDone, not empty")
    func allDoneIsDistinctFromEmpty() {
        let aggregate = AggregateState(sessions: [session(.done), session(.done)])
        #expect(aggregate.headline == .allDone)
    }

    @Test("no sessions at all reports empty")
    func noSessionsIsEmpty() {
        #expect(AggregateState(sessions: []).headline == .empty)
    }

    @Test("thinking and testing both count toward the active total")
    func activeCountIncludesThinkingAndTesting() {
        let aggregate = AggregateState(sessions: [session(.thinking), session(.testing), session(.working)])
        #expect(aggregate.activeCount == 3)
    }
}

extension AggregateState.Headline: Equatable {
    public static func == (lhs: AggregateState.Headline, rhs: AggregateState.Headline) -> Bool {
        switch (lhs, rhs) {
        case (.needsAttention(let a), .needsAttention(let b)): return a == b
        case (.error(let a), .error(let b)): return a == b
        case (.active(let a), .active(let b)): return a == b
        case (.waiting(let a), .waiting(let b)): return a == b
        case (.allDone, .allDone): return true
        case (.empty, .empty): return true
        default: return false
        }
    }
}
