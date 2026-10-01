import Foundation
import MochiCore
import Observation

/// The single source of truth for the running app: owns the session dictionary, settings,
/// and the background tasks that feed them (event ingestion, integration polling, the
/// once-a-second UI tick). Every view reads from this; nothing else mutates session state.
@MainActor
@Observable
public final class AppModel {
    private(set) public var sessions: [String: AgentSession] = [:]
    public var settings: MochiSettings {
        didSet {
            guard settings != oldValue else { return }
            persistence.save(settings)
        }
    }
    /// Bumped once a second so views computing elapsed time re-render. Reading `now` instead
    /// of calling `Date()` directly inside a view body is what makes that dependency explicit
    /// to SwiftUI's observation tracking.
    private(set) public var now: Date = Date()
    public var selectedSessionID: String?
    public var quarantineCount: Int = 0

    private let paths: MochiPaths
    private let persistence: PersistenceStore
    private let inbox: EventInbox
    private let notifications = NotificationManager()
    private var coordinator: IntegrationsCoordinator?
    private var tasks: [Task<Void, Never>] = []

    public init(paths: MochiPaths = .shared) {
        self.paths = paths
        self.persistence = PersistenceStore(paths: paths)
        self.inbox = EventInbox(paths: paths)
        self.settings = persistence.loadSettings()

        let snapshot = persistence.loadSessionSnapshot()
        for session in snapshot { sessions[session.id] = session }

        // Reconcile BEFORE the first render, synchronously — not on the next 30-second tick.
        // A persisted "working" session is historical evidence, not proof of current
        // liveness (a `mochi demo` run from hours ago, or a real agent that crashed without
        // a completion event, would otherwise flash as "Working" the instant Mochi opens).
        // This is also what makes `mochi demo`'s leftover sessions age out of a normal
        // launch on their own — see StaleDetector.reconcileLifecycle.
        StaleDetector.reconcileLifecycle(&sessions, now: Date())
    }

    public func start() {
        paths.ensureDirectoriesExist()

        tasks.append(Task { [weak self] in await self?.consumeEvents() })
        tasks.append(Task { [weak self] in await self?.consumeQuarantine() })
        tasks.append(Task { [weak self] in await self?.tick() })
        tasks.append(Task { [weak self] in await self?.periodicSnapshotSave() })

        Task { await notifications.requestAuthorizationIfNeeded() }

        let coordinator = IntegrationsCoordinator(entries: [
            .init(adapter: OpenClawAdapter(), interval: 15) { [weak self] in self?.settings.openClawIntegrationEnabled ?? false },
            .init(adapter: ProcessDiscoveryAdapter(), interval: 20) { [weak self] in self?.settings.processDetectionEnabled ?? false }
        ])
        coordinator.start()
        self.coordinator = coordinator
    }

    public func stop() {
        for task in tasks { task.cancel() }
        tasks.removeAll()
        coordinator?.stop()
    }

    // MARK: - Derived state

    public var aggregate: AggregateState {
        AggregateState(sessions: visibleSessions)
    }

    /// Sessions worth showing right now: finished ones age out after
    /// `settings.keepCompletedVisibleMinutes`, pure process-detection entries disappear
    /// shortly after the process does (their only evidence is "we polled and it was there"),
    /// and presumed-dead sessions age out on the same clock as finished ones — the popover is
    /// "what are my agents doing right now" (product spec section 10), not a permanent log,
    /// so a session from yesterday that silently died has no more business sitting among
    /// today's active ones than a long-finished one does.
    public var visibleSessions: [AgentSession] {
        let keepUntil = TimeInterval(settings.keepCompletedVisibleMinutes * 60)
        return sessions.values
            .filter { session in
                if session.discovery == .detected {
                    return now.timeIntervalSince(session.lastActivityAt) < 90
                }
                if session.status == .done, let finishedAt = session.finishedAt {
                    return now.timeIntervalSince(finishedAt) < keepUntil
                }
                if session.status == .offline {
                    return now.timeIntervalSince(session.lastActivityAt) < keepUntil
                }
                return true
            }
            .sorted { lhs, rhs in
                if lhs.status.sortPriority != rhs.status.sortPriority {
                    return lhs.status.sortPriority < rhs.status.sortPriority
                }
                return lhs.lastActivityAt > rhs.lastActivityAt
            }
    }

    public func session(id: String) -> AgentSession? { sessions[id] }

    /// Settings → Advanced → "Reset local history." Clears known sessions and everything on
    /// disk that feeds them (inbox, quarantine, processed, the snapshot) but leaves settings
    /// untouched. The live background loops keep running, so a currently-active OpenClaw
    /// session or a detected process reappears on the next poll — this clears history, not
    /// the integrations themselves.
    public func resetLocalHistory() {
        sessions.removeAll()
        quarantineCount = 0
        let fm = FileManager.default
        for dir in [paths.inbox, paths.quarantine, paths.processed] {
            if let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                for entry in entries { try? fm.removeItem(at: entry) }
            }
        }
        try? fm.removeItem(at: paths.sessionsStateFile)
    }

    // MARK: - Background loops

    private func consumeEvents() async {
        for await event in await inbox.events() {
            SessionReducer.apply(event, to: &sessions)
            await notifyIfNeeded(agentId: event.agentId)
        }
    }

    private func consumeQuarantine() async {
        for await _ in await inbox.quarantinedEvents() {
            quarantineCount += 1
        }
    }

    /// One tick per second drives elapsed-time display; every 30th tick also reconciles
    /// lifecycle state — sessions gone quiet long enough become `.stale`/`.offline`, expired
    /// demo sessions are removed outright, and detected-only processes that vanished are
    /// pruned (product spec section 24; see `StaleDetector.reconcileLifecycle`).
    private func tick() async {
        var counter = 0
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            now = Date()
            counter += 1
            if counter % 30 == 0 {
                StaleDetector.reconcileLifecycle(&sessions, now: now)
                pruneDetectedGhosts()
            }
        }
    }

    private func pruneDetectedGhosts() {
        for (id, session) in sessions where session.discovery == .detected {
            if now.timeIntervalSince(session.lastActivityAt) > 180 {
                sessions.removeValue(forKey: id)
            }
        }
    }

    private func periodicSnapshotSave() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            persistence.saveSessionSnapshot(Array(sessions.values))
        }
    }

    private func notifyIfNeeded(agentId: String) async {
        guard var session = sessions[agentId] else { return }
        switch session.status {
        case .done:
            guard settings.notifyOnCompleted, !session.completionNotified else { return }
            session.completionNotified = true
            sessions[agentId] = session
            await notifications.notifyCompleted(agentName: session.displayName, project: session.projectName, message: session.recentActivity.last?.message)

        case .needsPermission:
            guard settings.notifyOnAttention, !session.attentionNotified else { return }
            session.attentionNotified = true
            sessions[agentId] = session
            await notifications.notifyAttention(agentName: session.displayName, project: session.projectName, reason: session.attentionMessage ?? session.attentionReason?.friendlyLabel ?? "Needs your attention")

        case .error:
            guard settings.notifyOnError, !session.attentionNotified else { return }
            session.attentionNotified = true
            sessions[agentId] = session
            await notifications.notifyError(agentName: session.displayName, project: session.projectName, message: session.errorMessage ?? "Something went wrong")

        default:
            break
        }
    }
}
