import Foundation

/// The lifecycle state of an agent session.
///
/// This is intentionally a value type over raw strings (via `.custom`) rather than a closed
/// enum so that events from a newer protocol version, or a future integration we haven't
/// written yet, degrade to "unknown but preserved" instead of failing to decode.
public enum AgentStatus: Hashable, Sendable {
    case idle
    case starting
    case working
    case thinking
    case testing
    case waiting
    case needsPermission
    case paused
    case done
    case error
    /// We previously had evidence this session was active, but haven't heard anything —
    /// from an event, a heartbeat, or a reconcilable integration re-confirming it — in a
    /// while. Set by `StaleDetector.reconcileLifecycle`, never by an integration directly.
    /// This is what makes "persisted Working" stop silently meaning "currently working"
    /// once the evidence is old: the status itself changes, not just a display label next
    /// to an unchanged "Working" badge (a real bug this fixed — see docs/architecture.md).
    case stale
    /// No evidence of activity for long enough that Mochi presumes the session ended
    /// without telling it (crashed, force-quit, machine slept through completion). Also
    /// set only by reconciliation, never fabricated by an integration. Revisable: a fresh
    /// event for this session (the agent turns out to still be alive after all) overrides
    /// it like any other status, same as every other state here.
    case offline
    /// A status string we don't recognize. Preserved verbatim so UI can at least show it
    /// and `mochi doctor` can flag it, rather than silently coercing it to something wrong.
    case custom(String)

    public var rawValue: String {
        switch self {
        case .idle: return "idle"
        case .starting: return "starting"
        case .working: return "working"
        case .thinking: return "thinking"
        case .testing: return "testing"
        case .waiting: return "waiting"
        case .needsPermission: return "needsPermission"
        case .paused: return "paused"
        case .done: return "done"
        case .error: return "error"
        case .stale: return "stale"
        case .offline: return "offline"
        case .custom(let value): return value
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "idle": self = .idle
        case "starting": self = .starting
        case "working": self = .working
        case "thinking": self = .thinking
        case "testing": self = .testing
        case "waiting": self = .waiting
        case "needsPermission", "needs_permission": self = .needsPermission
        case "paused": self = .paused
        case "done", "completed": self = .done
        case "error", "failed": self = .error
        case "stale": self = .stale
        case "offline": self = .offline
        default: self = .custom(rawValue)
        }
    }

    /// Whether this status represents an agent actively doing something (counts toward
    /// the menu bar "N working" aggregate).
    public var isActive: Bool {
        switch self {
        case .starting, .working, .thinking, .testing: return true
        default: return false
        }
    }

    /// Whether this status requires the user's attention right now.
    public var needsAttention: Bool {
        switch self {
        case .needsPermission, .error: return true
        default: return false
        }
    }

    /// Terminal: nothing further will happen to this session without a brand new event.
    /// `.stale` is deliberately NOT terminal — it's a waypoint reconciliation can still move
    /// on to `.offline`, or a fresh event can move back to anything else.
    public var isTerminal: Bool {
        switch self {
        case .done, .error, .offline: return true
        default: return false
        }
    }

    /// Sort priority for lists and the menu bar aggregate: lower sorts first.
    /// Matches the product spec's priority: attention > errors > active > waiting > idle/done.
    /// `.stale` sits right after waiting: it's not urgent like an error, but it's more worth
    /// noticing than idle/done/offline busywork, since it used to be something you were
    /// trusting to be active.
    public var sortPriority: Int {
        switch self {
        case .needsPermission: return 0
        case .error: return 1
        case .working, .testing, .thinking: return 2
        case .waiting: return 3
        case .stale: return 4
        case .starting: return 5
        case .paused: return 6
        case .done: return 7
        case .idle: return 8
        case .offline: return 9
        case .custom: return 10
        }
    }

    /// Friendly, non-corporate copy for the UI. See product spec section 44.
    public var friendlyLabel: String {
        switch self {
        case .idle: return "Chilling"
        case .starting: return "Waking up"
        case .working: return "Working"
        case .thinking: return "Thinking"
        case .testing: return "Testing"
        case .waiting: return "Waiting"
        case .needsPermission: return "Needs you"
        case .paused: return "Paused"
        case .done: return "Done"
        case .error: return "Problem"
        case .stale: return "Stale"
        case .offline: return "Offline"
        case .custom(let value): return value.capitalized
        }
    }
}

extension AgentStatus: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self.init(rawValue: raw)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
