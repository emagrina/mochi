import Foundation

/// Why an agent is waiting on the user. Kept as a lightweight open string-backed enum since
/// integrations will keep inventing reasons we don't know about yet.
public enum AttentionReason: Hashable, Sendable, Codable {
    case permission
    case input
    case decision
    case other(String)

    public var rawValue: String {
        switch self {
        case .permission: return "permission"
        case .input: return "input"
        case .decision: return "decision"
        case .other(let value): return value
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "permission": self = .permission
        case "input": self = .input
        case "decision": self = .decision
        default: self = .other(rawValue)
        }
    }

    public var friendlyLabel: String {
        switch self {
        case .permission: return "Permission required"
        case .input: return "Waiting for input"
        case .decision: return "Waiting on a decision"
        case .other(let value): return value.isEmpty ? "Needs attention" : value
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Pull request metadata attached to a `completed` event, if the integration knows it.
public struct PullRequestInfo: Hashable, Sendable, Codable {
    public var number: Int?
    public var url: String?
    public var title: String?

    public init(number: Int? = nil, url: String? = nil, title: String? = nil) {
        self.number = number
        self.url = url
        self.title = title
    }
}

/// A single entry in an agent's recent-activity timeline, shown in the detail view.
public struct ActivityLogEntry: Hashable, Sendable, Codable, Identifiable {
    public var id: UUID
    public var timestamp: Date
    public var status: AgentStatus?
    public var message: String

    public init(id: UUID = UUID(), timestamp: Date, status: AgentStatus? = nil, message: String) {
        self.id = id
        self.timestamp = timestamp
        self.status = status
        self.message = message
    }
}

/// How we learned about an agent: a real integration reporting rich structured state,
/// versus merely noticing a process is running. Section 10 of the product spec is explicit
/// that these must never be visually conflated.
public enum DiscoveryKind: Hashable, Sendable, Codable {
    /// The agent (or an adapter acting on its behalf) is actively sending Mochi protocol events.
    case instrumented
    /// We only know a matching process exists. No activity detail is available.
    case detected
}
