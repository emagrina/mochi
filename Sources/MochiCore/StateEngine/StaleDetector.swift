import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Heuristics for "this agent probably crashed without telling us" (product spec section 24).
///
/// We never silently rewrite a session's status to `.done` just because it went quiet —
/// that would be claiming certainty we don't have. Instead we expose `isStale`/`isProcessAlive`
/// as *additional signals* the UI overlays on top of the last known status ("Last seen 27m ago").
public enum StaleDetector {
    /// How long an active/waiting/attention-needing session can go without any event before
    /// we consider it stale. Deliberately generous: agents legitimately go quiet mid-tool-call.
    public static let staleThreshold: TimeInterval = 20 * 60

    public static func isStale(_ session: AgentSession, now: Date = Date()) -> Bool {
        guard session.finishedAt == nil else { return false }
        switch session.status {
        case .working, .thinking, .testing, .starting, .waiting, .needsPermission:
            return now.timeIntervalSince(session.lastActivityAt) > staleThreshold
        default:
            return false
        }
    }

    /// Best-effort liveness check for a known PID. `kill(pid, 0)` succeeds (or fails with
    /// EPERM, meaning it exists but we don't own it) if the process exists; ESRCH means gone.
    /// This can only ever be *evidence*, not proof: PIDs get reused.
    public static func isProcessAlive(pid: Int32) -> Bool {
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }
}
