import Foundation

/// The Mochi event protocol, v1. See docs/protocol.md for the full specification.
///
/// This is the wire format any agent, script, or adapter uses to tell Mochi what's happening.
/// Every field except `version`, `event`, `agentId`, and `timestamp` is optional: integrations
/// provide whatever they know, and the state engine (`SessionReducer`) fills in the rest from
/// prior events or leaves it unknown.
public struct MochiEvent: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable {
        case start
        case status
        case activity
        case attention
        case completed
        case error
        case heartbeat
    }

    public var version: Int
    public var event: Kind
    /// The identifier for THIS RUN — historically named `agentId` in the wire format (kept
    /// for backward compatibility; see `docs/protocol.md`), but it has always really been a
    /// *session* identifier: Mochi dedicates one dictionary entry, one activity log, one row
    /// to each distinct value of this field. For the agent's own stable identity — who is
    /// doing the work, shared across many sessions — see `agentKey`/`agentDisplayName` below.
    public var agentId: String
    public var provider: String?
    /// Stable key for the agent itself, independent of this particular session. Omit it and
    /// Mochi treats this session as its own standalone agent (the original, still-default
    /// behavior); set it to the same value across multiple `start` calls to tell Mochi "these
    /// are different sessions of the same agent." Never the provider name — see
    /// `AgentIdentity`.
    public var agentKey: String?
    /// The agent's configured/custom display name, if one exists (e.g. OpenClaw's
    /// `identityName`, or a caller-supplied `--agent-name`). This becomes the PRIMARY title
    /// in the UI, ahead of `provider`.
    public var agentDisplayName: String?
    /// A role/persona descriptor, when distinct from `agentDisplayName`.
    public var agentRole: String?
    public var sessionId: String?
    public var project: String?
    public var projectPath: String?
    public var task: String?
    public var status: String?
    public var activity: String?
    public var message: String?
    public var attentionReason: String?
    public var error: String?
    public var pullRequest: PullRequestInfo?
    public var branch: String?
    public var repository: String?
    public var pid: Int32?
    public var metadata: [String: String]?
    public var timestamp: Date

    public init(
        version: Int = 1,
        event: Kind,
        agentId: String,
        provider: String? = nil,
        agentKey: String? = nil,
        agentDisplayName: String? = nil,
        agentRole: String? = nil,
        sessionId: String? = nil,
        project: String? = nil,
        projectPath: String? = nil,
        task: String? = nil,
        status: String? = nil,
        activity: String? = nil,
        message: String? = nil,
        attentionReason: String? = nil,
        error: String? = nil,
        pullRequest: PullRequestInfo? = nil,
        branch: String? = nil,
        repository: String? = nil,
        pid: Int32? = nil,
        metadata: [String: String]? = nil,
        timestamp: Date = Date()
    ) {
        self.version = version
        self.event = event
        self.agentId = agentId
        self.provider = provider
        self.agentKey = agentKey
        self.agentDisplayName = agentDisplayName
        self.agentRole = agentRole
        self.sessionId = sessionId
        self.project = project
        self.projectPath = projectPath
        self.task = task
        self.status = status
        self.activity = activity
        self.message = message
        self.attentionReason = attentionReason
        self.error = error
        self.pullRequest = pullRequest
        self.branch = branch
        self.repository = repository
        self.pid = pid
        self.metadata = metadata
        self.timestamp = timestamp
    }
}

extension MochiEvent {
    public static let currentVersion = 1

    public enum ValidationError: Error, CustomStringConvertible {
        case unsupportedVersion(Int)
        case emptyAgentId

        public var description: String {
            switch self {
            case .unsupportedVersion(let v): return "unsupported protocol version \(v)"
            case .emptyAgentId: return "agentId must not be empty"
            }
        }
    }

    /// Minimal structural validation. We deliberately do NOT reject unknown future fields
    /// (JSONDecoder ignores them already) and we accept any version <= currentVersion,
    /// since v1 is forward-compatible by construction (new optional fields only).
    public func validate() throws {
        guard !agentId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.emptyAgentId
        }
        guard version > 0 && version <= MochiEvent.currentVersion else {
            throw ValidationError.unsupportedVersion(version)
        }
    }
}

extension MochiEvent {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = MochiDateCoding.jsonEncodingStrategy
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = MochiDateCoding.jsonDecodingStrategy
        return decoder
    }()

    public func encoded() throws -> Data {
        try MochiEvent.encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> MochiEvent {
        try decoder.decode(MochiEvent.self, from: data)
    }
}
