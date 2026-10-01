import Foundation

/// The full known state of one agent session, built up by folding `MochiEvent`s over time.
///
/// This is the UI-agnostic source of truth. `MochiApp` renders it; the CLI's `inspect`/`list`
/// commands print it; tests exercise it directly. Every field beyond `id`/`status` is optional
/// because no single integration provides all of them (section 5 of the product spec).
public struct AgentSession: Identifiable, Hashable, Sendable, Codable {
    public var id: String
    public var provider: AgentProvider
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
        self.provider = provider
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

    public var elapsed: TimeInterval {
        (finishedAt ?? Date()).timeIntervalSince(startedAt)
    }

    public var timeSinceLastActivity: TimeInterval {
        Date().timeIntervalSince(lastActivityAt)
    }

    public var displayName: String {
        provider.displayName
    }
}
