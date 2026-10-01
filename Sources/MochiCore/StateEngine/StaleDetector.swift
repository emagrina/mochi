import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Turns silence into truthful status, not just a display hint.
///
/// This used to be a pure query (`isStale`) that the UI consulted to decide what *text* to
/// show, while the session's actual `status` sat frozen at whatever an integration last said
/// — which meant a session could display "Working" and "Last seen 47m ago" in the same row,
/// and worse, a persisted "working" status from a `mochi demo` run (or a real agent that
/// crashed) would survive forever across app restarts with nothing to ever change it. That
/// was a real bug: normal `Mochi.app` launches were showing hours-old demo sessions as
/// currently active. `reconcileLifecycle` is the fix — it actively moves a quiet session's
/// `status` through `.stale` and on to `.offline`, so "Working" in the UI always means
/// *currently* working, not just "the last thing we heard."
///
/// Still never claims more than it knows: `.stale`/`.offline` are evidence-of-silence, not
/// evidence-of-death, and a single fresh event for the same session (the agent turns out to
/// still be running) overrides either exactly like any other status, via the normal event
/// pipeline in `SessionReducer` — reconciliation never blocks that.
public enum StaleDetector {
    /// How long an active/waiting/attention-needing session can go without any event before
    /// we stop trusting its last known status at face value and call it `.stale`.
    /// Deliberately generous: agents legitimately go quiet mid-tool-call.
    public static let staleThreshold: TimeInterval = 20 * 60

    /// How long with zero evidence before we call it `.offline` — a much higher bar than
    /// `.stale`, since this is "presumed gone," not just "haven't heard from it in a while."
    public static let offlineThreshold: TimeInterval = 90 * 60

    /// How long a `demo`-sourced session sticks around after its last event, regardless of
    /// status. Short and unconditional on purpose: demo data exists only to exercise the UI
    /// and must never be mistaken for a real session (see `SessionSource.demo`). This is
    /// long enough to actually look at the result of a `mochi demo` run, short enough that it
    /// cannot plausibly still be there the next time you launch Mochi for real work.
    public static let demoRetention: TimeInterval = 2 * 60

    /// Reconciles every session against the clock: demo sessions past their retention window
    /// are removed outright; non-demo, instrumented sessions that have gone quiet move from
    /// their last active status to `.stale`, and from there (or directly, if the silence is
    /// long enough) to `.offline`. Finished sessions (`done`/`error`), already-`.offline`
    /// sessions, and passively-detected sessions (handled by their own, much shorter, prune
    /// window — see `AppModel.pruneDetectedGhosts`) are left alone.
    ///
    /// Called from three places, deliberately: once synchronously right after `AppModel`
    /// loads its persisted snapshot (so a freshly-launched Mochi never even flashes a stale
    /// "Working" before correcting itself), again on every periodic tick thereafter, and
    /// inside `SessionProjection.replayAll` so `mochi list`/`inspect`/`doctor` are truthful
    /// even when the app isn't running at all.
    public static func reconcileLifecycle(_ sessions: inout [String: AgentSession], now: Date = Date()) {
        for id in Array(sessions.keys) {
            guard let session = sessions[id] else { continue }

            if session.source == .demo {
                if now.timeIntervalSince(session.lastActivityAt) > demoRetention {
                    sessions.removeValue(forKey: id)
                }
                continue
            }

            guard session.discovery == .instrumented else { continue }
            guard !session.status.isTerminal else { continue }

            let quiet = now.timeIntervalSince(session.lastActivityAt)
            var updated = session
            if quiet > offlineThreshold {
                updated.status = .offline
            } else if quiet > staleThreshold, isAwaitingEvidence(session.status) {
                updated.status = .stale
            } else {
                continue
            }
            sessions[id] = updated
        }
    }

    /// Statuses that represent "we believe something is currently happening" — the ones
    /// reconciliation can downgrade to `.stale` once the evidence for that belief goes quiet.
    private static func isAwaitingEvidence(_ status: AgentStatus) -> Bool {
        status.isActive || status == .waiting || status == .needsPermission
    }

    /// Best-effort liveness check for a known PID. `kill(pid, 0)` succeeds (or fails with
    /// EPERM, meaning it exists but we don't own it) if the process exists; ESRCH means gone.
    /// This can only ever be *evidence*, not proof: PIDs get reused.
    public static func isProcessAlive(pid: Int32) -> Bool {
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }
}
