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
    public var agentId: String
    public var provider: String?
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
