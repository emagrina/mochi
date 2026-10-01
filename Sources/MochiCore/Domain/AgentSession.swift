import Foundation

/// The full known state of one agent session, built up by folding `MochiEvent`s over time.
///
/// This is the UI-agnostic source of truth. `MochiApp` renders it; the CLI's `inspect`/`list`
/// commands print it; tests exercise it directly. Every field beyond `id`/`status` is optional
/// because no single integration provides all of them (section 5 of the product spec).
public struct AgentSession: Identifiable, Hashable, Sendable, Codable {
    public var id: String
    /// WHO is doing the work — see `AgentIdentity`'s doc comment for why this is a separate
    /// type from the session itself. `provider` below is a convenience passthrough, not a
    /// second source of truth: it always reads `agentIdentity.provider`.
    public var agentIdentity: AgentIdentity
    public var provider: AgentProvider { agentIdentity.provider }
    /// WHERE this session's events came from — see `SessionSource`. Set once, from the
    /// first event that creates this session; see `SessionReducer`.
    public var source: SessionSource
    public var sessionId: String?
    public var projectName: String?
    public var projectPath: String?
    public var currentTask: String?
    public var currentActivity: String?
    public var status: AgentStatus
    public var discovery: DiscoveryKind
    public var startedAt: Date
    public var lastActivityAt: Date
    public var finishedAt: Date?
    public var pid: Int32?
    public var branch: String?
    public var repository: String?
    public var pullRequest: PullRequestInfo?
    public var errorMessage: String?
    public var attentionReason: AttentionReason?
    public var attentionMessage: String?
    public var metadata: [String: String]
    public var recentActivity: [ActivityLogEntry]
    /// Set once we've delivered a notification for the current attention/error condition,
    /// so `NotificationManager` never repeats itself (product spec section 37: "ONE notification").
    public var attentionNotified: Bool
    /// Same idea for the one-time "finished" notification.
    public var completionNotified: Bool

    public init(
        id: String,
        provider: AgentProvider,
        agentIdentity: AgentIdentity? = nil,
        source: SessionSource = .unknown,
        sessionId: String? = nil,
        projectName: String? = nil,
        projectPath: String? = nil,
        currentTask: String? = nil,
        currentActivity: String? = nil,
        status: AgentStatus = .starting,
        discovery: DiscoveryKind = .instrumented,
        startedAt: Date = Date(),
        lastActivityAt: Date = Date(),
        finishedAt: Date? = nil,
        pid: Int32? = nil,
        branch: String? = nil,
        repository: String? = nil,
        pullRequest: PullRequestInfo? = nil,
        errorMessage: String? = nil,
        attentionReason: AttentionReason? = nil,
        attentionMessage: String? = nil,
        metadata: [String: String] = [:],
        recentActivity: [ActivityLogEntry] = [],
        attentionNotified: Bool = false,
        completionNotified: Bool = false
    ) {
        self.id = id
        self.agentIdentity = agentIdentity ?? AgentIdentity(key: id, provider: provider)
        self.source = source
        self.sessionId = sessionId
        self.projectName = projectName
        self.projectPath = projectPath
        self.currentTask = currentTask
        self.currentActivity = currentActivity
        self.status = status
        self.discovery = discovery
        self.startedAt = startedAt
        self.lastActivityAt = lastActivityAt
        self.finishedAt = finishedAt
        self.pid = pid
        self.branch = branch
        self.repository = repository
        self.pullRequest = pullRequest
        self.errorMessage = errorMessage
        self.attentionReason = attentionReason
        self.attentionMessage = attentionMessage
        self.metadata = metadata
        self.recentActivity = recentActivity
        self.attentionNotified = attentionNotified
        self.completionNotified = completionNotified
    }

    // Custom decoding so a session persisted by an older version of Mochi — missing fields
    // added since, like `source` — loads with a safe default instead of failing. This
    // matters more than it looks: `PersistenceStore` decodes the *entire* session snapshot
    // as one JSON array, and `Array<Decodable>.decode` fails the whole array if a single
    // element throws, which would have silently wiped every session, not just the old one.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        let decodedIdentity = try container.decodeIfPresent(AgentIdentity.self, forKey: .agentIdentity)
        agentIdentity = decodedIdentity ?? AgentIdentity(key: id, provider: .generic("unknown"))
        source = try container.decodeIfPresent(SessionSource.self, forKey: .source) ?? .unknown
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        projectName = try container.decodeIfPresent(String.self, forKey: .projectName)
        projectPath = try container.decodeIfPresent(String.self, forKey: .projectPath)
        currentTask = try container.decodeIfPresent(String.self, forKey: .currentTask)
        currentActivity = try container.decodeIfPresent(String.self, forKey: .currentActivity)
        status = try container.decodeIfPresent(AgentStatus.self, forKey: .status) ?? .custom("unknown")
        discovery = try container.decodeIfPresent(DiscoveryKind.self, forKey: .discovery) ?? .instrumented
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        lastActivityAt = try container.decodeIfPresent(Date.self, forKey: .lastActivityAt) ?? startedAt
        finishedAt = try container.decodeIfPresent(Date.self, forKey: .finishedAt)
        pid = try container.decodeIfPresent(Int32.self, forKey: .pid)
        branch = try container.decodeIfPresent(String.self, forKey: .branch)
        repository = try container.decodeIfPresent(String.self, forKey: .repository)
        pullRequest = try container.decodeIfPresent(PullRequestInfo.self, forKey: .pullRequest)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        attentionReason = try container.decodeIfPresent(AttentionReason.self, forKey: .attentionReason)
        attentionMessage = try container.decodeIfPresent(String.self, forKey: .attentionMessage)
        metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
        recentActivity = try container.decodeIfPresent([ActivityLogEntry].self, forKey: .recentActivity) ?? []
        attentionNotified = try container.decodeIfPresent(Bool.self, forKey: .attentionNotified) ?? false
        completionNotified = try container.decodeIfPresent(Bool.self, forKey: .completionNotified) ?? false
    }

    public var elapsed: TimeInterval {
        (finishedAt ?? Date()).timeIntervalSince(startedAt)
    }

    public var timeSinceLastActivity: TimeInterval {
        Date().timeIntervalSince(lastActivityAt)
    }

    /// The resolved primary title for this session — the agent's identity, not the runtime
    /// that happens to be executing it. See `AgentIdentity.title`.
    public var displayName: String {
        agentIdentity.title
    }
}
