import Foundation

/// Translates OpenClaw's state into Mochi protocol events by polling its own CLI — never by
/// patching OpenClaw or reading its SQLite stores directly.
///
/// What's actually verified locally (OpenClaw 2026.9.7), see docs/integrations.md:
///   - `openclaw sessions list --json --all-agents --active <minutes>` is a supported,
///     documented, read-only CLI surface. Each session carries a real `status` field
///     ("running", "done", ...) which we translate directly — SUPPORTED, not a guess. What's
///     still HEURISTIC/missing: OpenClaw exposes no fine-grained activity, so Mochi can only
///     show working/done/idle, never "thinking"/"testing". The `--active` bound is load-
///     bearing: without it this call returns the tool's *entire* session history (every cron
///     run, every subagent, ever) — discovered by running this against a real, long-lived
///     install while building it. We also deliberately ignore `abortedLastRun`: it showed up
///     `true` on ordinary, non-failed sessions in local testing, so it isn't a trustworthy
///     "something went wrong" signal.
///   - `openclaw approvals pending --json` is a supported CLI surface for exec/plugin/
///     system-agent approvals via the Gateway. This is the real, non-guessed signal for
///     "needs you" the product spec asks for (section 37) — but we could not exercise it
///     against a live pending approval while building this, so the field names used to
///     correlate an approval back to a specific agent/session are EXPERIMENTAL and may need
///     adjustment; we degrade gracefully (skip the approval, keep the ones we can parse)
///     rather than guess wrong.
///   - `openclaw agents list --json` maps agent ids to `identityName` (the real, configured
///     display name — "Chief of Staff", "Developer" — used as the row's PRIMARY title, not
///     "OpenClaw") and `workspace` (used for `projectPath` and the "Open Project"/"Open
///     Terminal" actions).
///   - A genuine push-based integration is possible: `openclaw plugins init --type feature`
///     scaffolds a real plugin, and `openclaw hooks list` shows OpenClaw's own bundled hooks
///     fire on events like `gateway:startup`/`command`/`session:compact:*`. Building a
///     custom hook plugin that calls the Mochi CLI directly is NOT implemented in v1 — it
///     needs the user's own OpenClaw plugin install/enable/restart flow to verify, so it's
///     documented as a next step rather than shipped half-verified.
///
/// This is an `actor`, not a `struct`, specifically so it can remember what it saw on the
/// *previous* poll (see `previouslyActiveStatuses`) — that memory is what lets it notice a
/// session has disappeared from OpenClaw's own active list and say so immediately, rather
/// than only going quiet and waiting for the generic time-based staleness fallback
/// (`StaleDetector.staleThreshold`, 20 minutes) to catch up. `IntegrationsCoordinator` only
/// ever calls one adapter instance's `pollOnce` sequentially, never concurrently with itself,
/// so actor isolation here is about safe mutable state across calls, not contention.
public actor OpenClawAdapter: IntegrationAdapter {
    public nonisolated let id = "openclaw"
    public nonisolated let displayName = "OpenClaw"
    public nonisolated let reliability: IntegrationReliability = .heuristic

    /// How far back to ask OpenClaw for sessions. Bounds both the noise (don't import its
    /// entire history) and the request cost.
    private let activeWindow: TimeInterval = 30 * 60

    /// OpenClaw session key → the Mochi status we last mapped it to, for every session we saw
    /// actively working/waiting last poll. A key that drops out of this poll's results after
    /// being in here is real evidence it's no longer in OpenClaw's own active list — see
    /// `pollSessions`. Only active-ish statuses are kept (never `.done`/`.error`), so a
    /// legitimately finished session dropping out of the `--active` window later is never
    /// mistaken for a disappearance.
    private var previouslyActiveStatuses: [String: AgentStatus] = [:]

    public init() {}

    public func currentStatus() async -> IntegrationStatus {
        let result = await ProcessRunner.run("openclaw", ["--version"], timeout: 3)
        if result.exitCode == 0 {
            return .connected
        }
        return .notConfigured
    }

    public func pollOnce(into writer: EventWriter) async {
        let agentsById = await fetchAgents()
        await pollSessions(agentsById: agentsById, writer: writer)
        await pollApprovals(writer: writer)
    }

    // MARK: - Sessions

    private func pollSessions(agentsById: [String: AgentInfo], writer: EventWriter) async {
        // `--active N` is load-bearing, not an optimization: without it this returns OpenClaw's
        // *entire* session history (every cron run, every subagent spawn, ever), which would
        // flood Mochi with dozens of irrelevant rows. Verified against a real, long-lived
        // OpenClaw install while building this — the unfiltered call is unusable in practice.
        let result = await ProcessRunner.run(
            "openclaw",
            ["sessions", "list", "--json", "--all-agents", "--active", "\(Int(activeWindow / 60))", "--limit", "100"],
            timeout: 8
        )
        guard result.exitCode == 0,
              let root = try? JSONSerialization.jsonObject(with: result.stdout) as? [String: Any],
              let sessions = root["sessions"] as? [[String: Any]] else { return }

        var stillActive: [String: AgentStatus] = [:]

        for session in sessions {
            guard let key = session["key"] as? String else { continue }
            let agentId = "openclaw:\(key)"
            // Session keys look like "agent:<agentId>:<kind>:<uuid>" (e.g.
            // "agent:lead:dashboard:cb34...") or just "agent:<agentId>:main" for the default
            // session — verified against this machine's real sessions. `openClawAgentId` is
            // OpenClaw's own stable agent slug (shared by every session of that agent);
            // `sessionKind` ("dashboard", "acp", "cron", "main", ...) distinguishes *which*
            // session of that agent this is, which is exactly what's needed so two rows for
            // the same agent (e.g. two "Chief of Staff" sessions) read as distinguishable
            // rather than as an ambiguous duplicate.
            let keyParts = key.split(separator: ":").map(String.init)
            let openClawAgentId = keyParts.count > 1 ? keyParts[1] : nil
            let sessionKind = keyParts.count > 2 ? keyParts[2] : nil
            let agentInfo = openClawAgentId.flatMap { agentsById[$0] }

            // OpenClaw's own `status` field ("running", "done", ...) is the real signal —
            // verified locally. We only translate "running" into Mochi's vocabulary;
            // anything else (including a future status we don't know about) passes through
            // via `AgentStatus(rawValue:)`, which already falls back to `.custom(...)` rather
            // than guessing. We deliberately do NOT treat `abortedLastRun` as an error: it
            // turned up `true` on ordinary, non-failed sessions in local testing, so it isn't
            // a trustworthy "something went wrong" signal.
            let rawStatus = (session["status"] as? String) ?? "idle"
            let status = rawStatus.lowercased() == "running" ? AgentStatus.working : AgentStatus(rawValue: rawStatus)

            if status.isActive || status == .waiting || status == .needsPermission {
                stillActive[key] = status
            }

            let event = MochiEvent(
                event: .status,
                agentId: agentId,
                provider: "openclaw",
                agentKey: openClawAgentId.map { "openclaw:\($0)" },
                agentDisplayName: agentInfo?.identityName,
                source: SessionSource.openClaw.rawValue,
                sessionId: session["sessionId"] as? String,
                project: Self.sessionKindLabel(sessionKind),
                projectPath: agentInfo?.workspace,
                task: session["label"] as? String,
                status: status.rawValue,
                message: nil,
                metadata: ["openclawSessionKey": key],
                timestamp: Date()
            )
            _ = try? writer.write(event)
        }

        // Real reconciliation, not just a timeout: a session we previously saw as active that
        // is simply absent from this fresh poll is positive evidence OpenClaw itself no longer
        // considers it active — worth reporting as `.stale` right now rather than waiting up to
        // `StaleDetector.staleThreshold` (20 minutes) of silence to notice on its own. Not
        // `.offline`: disappearing from the list doesn't tell us whether it finished cleanly
        // (and just aged out of OpenClaw's own window) or crashed, so `.stale` — "no longer
        // confirmed," not "presumed dead" — is the honest signal here.
        let disappeared = Set(previouslyActiveStatuses.keys).subtracting(stillActive.keys)
        for key in disappeared {
            let event = MochiEvent(
                event: .status,
                agentId: "openclaw:\(key)",
                provider: "openclaw",
                source: SessionSource.openClaw.rawValue,
                status: AgentStatus.stale.rawValue,
                message: "No longer visible in OpenClaw's active session list.",
                metadata: ["openclawSessionKey": key],
                timestamp: Date()
            )
            _ = try? writer.write(event)
        }
        previouslyActiveStatuses = stillActive
    }

    /// A human label for the kind of session this is, when it adds information beyond "this
    /// is the agent's main session" (which gets no label at all, since that's the default
    /// and unremarkable case). Unknown/future kind tokens degrade to their raw, capitalized
    /// form rather than being dropped — still real information, just not one we have a nicer
    /// name for yet.
    private static func sessionKindLabel(_ kind: String?) -> String? {
        guard let kind, kind != "main" else { return nil }
        switch kind {
        case "dashboard": return "Dashboard session"
        case "acp": return "ACP session"
        case "cron": return "Scheduled run"
        case "subagent": return "Subagent"
        default: return kind.capitalized
        }
    }

    // MARK: - Approvals (needs-you detection)

    private func pollApprovals(writer: EventWriter) async {
        let result = await ProcessRunner.run("openclaw", ["approvals", "pending", "--json", "--timeout", "4000"], timeout: 6)
        guard result.exitCode == 0,
              let root = try? JSONSerialization.jsonObject(with: result.stdout) as? [String: Any],
              let approvals = root["approvals"] as? [[String: Any]] else { return }

        let identifierKeys = ["agentId", "sessionId", "session", "agent", "id"]
        let reasonKeys = ["reason", "summary", "command", "message", "description"]

        for approval in approvals {
            guard let identifier = identifierKeys.compactMap({ approval[$0] as? String }).first else { continue }
            let reason = reasonKeys.compactMap { approval[$0] as? String }.first ?? "OpenClaw is waiting for your approval."
            let event = MochiEvent(
                event: .attention,
                agentId: "openclaw:\(identifier)",
                provider: "openclaw",
                source: SessionSource.openClaw.rawValue,
                status: AgentStatus.needsPermission.rawValue,
                message: reason,
                attentionReason: "permission",
                timestamp: Date()
            )
            _ = try? writer.write(event)
        }
    }

    // MARK: - Agents

    private struct AgentInfo {
        let identityName: String?
        let workspace: String?
    }

    private func fetchAgents() async -> [String: AgentInfo] {
        let result = await ProcessRunner.run("openclaw", ["agents", "list", "--json"], timeout: 5)
        guard result.exitCode == 0,
              let array = try? JSONSerialization.jsonObject(with: result.stdout) as? [[String: Any]] else { return [:] }
        var map: [String: AgentInfo] = [:]
        for entry in array {
            guard let id = entry["id"] as? String else { continue }
            map[id] = AgentInfo(identityName: entry["identityName"] as? String, workspace: entry["workspace"] as? String)
        }
        return map
    }
}
