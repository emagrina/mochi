import Foundation

/// Centralized rollup of all sessions, computed once and shared by the menu bar icon, the
/// popover header, and the widget — so "what badge do we show" logic lives in exactly one
/// place (product spec section 47).
public struct AggregateState: Hashable, Sendable {
    public var total: Int
    public var working: Int
    public var testing: Int
    public var thinking: Int
    public var waiting: Int
    public var needsAttention: Int
    public var errors: Int
    public var done: Int
    public var idle: Int

    public static let empty = AggregateState(
        total: 0, working: 0, testing: 0, thinking: 0, waiting: 0,
        needsAttention: 0, errors: 0, done: 0, idle: 0
    )

    public init(total: Int, working: Int, testing: Int, thinking: Int, waiting: Int, needsAttention: Int, errors: Int, done: Int, idle: Int) {
        self.total = total
        self.working = working
        self.testing = testing
        self.thinking = thinking
        self.waiting = waiting
        self.needsAttention = needsAttention
        self.errors = errors
        self.done = done
        self.idle = idle
    }

    public init(sessions: [AgentSession]) {
        var working = 0, testing = 0, thinking = 0, waiting = 0, needsAttention = 0, errors = 0, done = 0, idle = 0
        for session in sessions {
            switch session.status {
            case .working, .starting: working += 1
            case .testing: testing += 1
            case .thinking: thinking += 1
            case .waiting: waiting += 1
            case .needsPermission: needsAttention += 1
            case .error: errors += 1
            case .done: done += 1
            case .idle, .paused, .offline, .custom: idle += 1
            }
        }
        self.init(
            total: sessions.count, working: working, testing: testing, thinking: thinking,
            waiting: waiting, needsAttention: needsAttention, errors: errors, done: done, idle: idle
        )
    }

    public var activeCount: Int { working + testing + thinking }

    /// Priority order for the menu bar icon: attention > errors > active > waiting > idle.
    public enum Headline: Sendable {
        case needsAttention(Int)
        case error(Int)
        case active(Int)
        case waiting(Int)
        case allDone
        case empty
    }

    public var headline: Headline {
        if needsAttention > 0 { return .needsAttention(needsAttention) }
        if errors > 0 { return .error(errors) }
        if activeCount > 0 { return .active(activeCount) }
        if waiting > 0 { return .waiting(waiting) }
        if total == 0 { return .empty }
        return .allDone
    }

    /// Short, friendly summary line for the popover footer. Section 16: personality, but clear.
    public var summaryLine: String {
        switch headline {
        case .empty:
            return "No Mochis working right now."
        case .needsAttention(let count):
            return count == 1 ? "1 needs you." : "\(count) need you."
        case .error(let count):
            return count == 1 ? "1 hit a problem." : "\(count) hit problems."
        case .active(let count):
            let chilling = idle
            if chilling > 0 {
                return "\(count) working · \(chilling) chilling"
            }
            return count == 1 ? "1 working" : "\(count) working"
        case .waiting(let count):
            return count == 1 ? "1 waiting" : "\(count) waiting"
        case .allDone:
            return "Everyone's done ✨"
        }
    }
}
