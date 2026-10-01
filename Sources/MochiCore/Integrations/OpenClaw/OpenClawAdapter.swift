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
///     `true` on ordinary, non-failed sessions in that same testing, so treating it as an
///     error signal would have produced false "problem" notifications.
///   - `openclaw approvals pending --json` is a supported CLI surface for exec/plugin/
///     system-agent approvals via the Gateway. This is the real, non-guessed signal for
///     "needs you" the product spec asks for (section 37) — but we could not exercise it
///     against a live pending approval while building this, so the field names used to
///     correlate an approval back to a specific agent/session are EXPERIMENTAL and may need
///     adjustment; we degrade gracefully (skip the approval, keep the ones we can parse)
///     rather than guess wrong.
///   - `openclaw agents list --json` maps agent ids to workspace directories — used to fill
///     in `projectPath`/`projectName` for sessions we can attribute to a known agent.
///   - A genuine push-based integration is possible: `openclaw plugins init --type feature`
///     scaffolds a real plugin, and `openclaw hooks list` shows OpenClaw's own bundled hooks
///     fire on events like `gateway:startup`/`command`/`session:compact:*`. Building a
///     custom hook plugin that calls the Mochi CLI directly is NOT implemented in v1 — it
///     needs the user's own OpenClaw plugin install/enable/restart flow to verify, so it's
///     documented as a next step rather than shipped half-verified.
public struct OpenClawAdapter: IntegrationAdapter {
    public let id = "openclaw"
    public let displayName = "OpenClaw"
    public let reliability: IntegrationReliability = .heuristic

    /// How far back to ask OpenClaw for sessions. Bounds both the noise (don't import its
    /// entire history) and the request cost.
    private let activeWindow: TimeInterval = 30 * 60

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

        for session in sessions {
            guard let key = session["key"] as? String else { continue }
            let agentId = "openclaw:\(key)"
            let openClawAgentId = key.split(separator: ":").dropFirst().first.map(String.init)
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

            let event = MochiEvent(
                event: .status,
                agentId: agentId,
                provider: "openclaw",
                sessionId: session["sessionId"] as? String,
                project: agentInfo?.identityName ?? openClawAgentId,
                projectPath: agentInfo?.workspace,
                task: session["label"] as? String,
                status: status.rawValue,
                message: nil,
                metadata: ["openclawSessionKey": key],
                timestamp: Date()
            )
            _ = try? writer.write(event)
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
