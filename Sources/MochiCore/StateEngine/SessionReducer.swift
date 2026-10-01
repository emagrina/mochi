import Foundation

/// The single place that folds a `MochiEvent` into the session dictionary. Both the live
/// app (fed by `EventInbox`'s stream) and the CLI's read-only commands (which replay history
/// from disk, since the app may not be running) go through this exact function, so there is
/// never a second copy of "what does a status event mean" logic to drift out of sync.
public enum SessionReducer {
    public static let maxHistoryPerSession = 50

    /// Applies `event` to `sessions`, mutating in place. Out-of-order delivery is handled by
    /// only letting an event move "current state" fields backward in time if it's newer than
    /// what we've already applied; every event still lands in `recentActivity` (inserted in
    /// timestamp order) so the history list stays accurate even if events arrive jumbled.
    public static func apply(_ event: MochiEvent, to sessions: inout [String: AgentSession]) {
        var session = sessions[event.agentId] ?? AgentSession(
            id: event.agentId,
            provider: AgentProvider(rawValue: event.provider ?? "generic"),
            status: .starting,
            discovery: event.metadata?["mochi.discoveryKind"] == "detected" ? .detected : .instrumented,
            startedAt: event.timestamp,
            lastActivityAt: event.timestamp
        )

        let isNewer = event.timestamp >= session.lastActivityAt

        // Fields that make sense to backfill once, the first time we see them, regardless
        // of event ordering (identity-ish information rather than "current state").
        if session.sessionId == nil { session.sessionId = event.sessionId }
        if let provider = event.provider { session.provider = AgentProvider(rawValue: provider) }
        if session.projectName == nil { session.projectName = event.project }
        if session.projectPath == nil { session.projectPath = event.projectPath }
        if let metadata = event.metadata {
            session.metadata.merge(metadata) { _, new in new }
        }
        if let pid = event.pid { session.pid = pid }
        if let branch = event.branch { session.branch = branch }
        if let repository = event.repository { session.repository = repository }

        if isNewer {
            session.lastActivityAt = event.timestamp
            if let task = event.task { session.currentTask = task }
            if let activity = event.activity { session.currentActivity = activity }

            switch event.event {
            case .start:
                session.startedAt = event.timestamp
                session.status = event.status.map(AgentStatus.init(rawValue:)) ?? .starting
                session.finishedAt = nil
                session.errorMessage = nil
                session.attentionReason = nil
                session.attentionMessage = nil
                session.attentionNotified = false
                session.completionNotified = false

            case .status, .activity:
                if let status = event.status {
                    session.status = AgentStatus(rawValue: status)
                }
                if session.status != .needsPermission && session.status != .error {
                    session.attentionReason = nil
                    session.attentionMessage = nil
                    session.attentionNotified = false
                }

            case .attention:
                session.status = event.status.map(AgentStatus.init(rawValue:)) ?? .needsPermission
                session.attentionReason = event.attentionReason.map(AttentionReason.init(rawValue:))
                session.attentionMessage = event.message
                session.attentionNotified = false

            case .completed:
                session.status = event.status.map(AgentStatus.init(rawValue:)) ?? .done
                session.finishedAt = event.timestamp
                session.pullRequest = event.pullRequest
                session.attentionReason = nil
                session.attentionMessage = nil

            case .error:
                session.status = event.status.map(AgentStatus.init(rawValue:)) ?? .error
                session.errorMessage = event.message ?? event.error
                session.attentionNotified = false

            case .heartbeat:
                break // lastActivityAt bump only; no state change.
            }
        }

        if event.event != .heartbeat, let logMessage = logMessage(for: event) {
            let entry = ActivityLogEntry(timestamp: event.timestamp, status: event.status.map(AgentStatus.init(rawValue:)), message: logMessage)
            insert(entry, into: &session.recentActivity)
        }

        sessions[event.agentId] = session
    }

    private static func logMessage(for event: MochiEvent) -> String? {
        if let message = event.message, !message.isEmpty { return message }
        switch event.event {
        case .start: return "Started"
        case .status: return event.status.map { "Status: \($0)" }
        case .activity: return event.activity
        case .attention: return "Needs attention"
        case .completed: return "Completed"
        case .error: return event.error ?? "Error"
        case .heartbeat: return nil
        }
    }

    private static func insert(_ entry: ActivityLogEntry, into log: inout [ActivityLogEntry]) {
        // Guard against exact re-delivery (e.g. a retried CLI call) producing duplicate lines.
        if log.contains(where: { $0.timestamp == entry.timestamp && $0.message == entry.message }) {
            return
        }
        let index = log.firstIndex { $0.timestamp > entry.timestamp } ?? log.count
        log.insert(entry, at: index)
        if log.count > maxHistoryPerSession {
            log.removeFirst(log.count - maxHistoryPerSession)
        }
    }
}
