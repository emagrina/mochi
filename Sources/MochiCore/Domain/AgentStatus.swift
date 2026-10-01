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

    public var isTerminal: Bool {
        switch self {
        case .done, .error, .offline: return true
        default: return false
        }
    }

    /// Sort priority for lists and the menu bar aggregate: lower sorts first.
    /// Matches the product spec's priority: attention > errors > active > waiting > idle/done.
    public var sortPriority: Int {
        switch self {
        case .needsPermission: return 0
        case .error: return 1
        case .working, .testing, .thinking: return 2
        case .waiting: return 3
        case .starting: return 4
        case .paused: return 5
        case .done: return 6
        case .idle: return 7
        case .offline: return 8
        case .custom: return 9
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
