import Foundation

/// WHO is doing the work, independent of any one run.
///
/// This is deliberately a separate type from `AgentSession`: a single agent (e.g. OpenClaw's
/// "Chief of Staff" persona) can have many sessions over time — a main conversation, a
/// dashboard sub-thread, a spawned subagent run — and all of them should present the same
/// agent identity while remaining individually trackable by session id. Before this type
/// existed, `AgentSession` conflated the two: its only identity field was the session id, and
/// the UI fell back to showing the *provider* ("OpenClaw", "Claude") as the primary title,
/// which answers "which runtime ran this" rather than "which agent is this" — the wrong
/// question for someone glancing at the menu bar to see who's doing what.
///
/// `provider` ("openclaw", "claude", "codex", ...) is never the identity itself — see `title`.
public struct AgentIdentity: Hashable, Sendable, Codable {
    /// A stable key for the agent itself, shared by every session that agent runs. For
    /// OpenClaw this is `"openclaw:<agentId>"`, constant across that agent's sessions. For a
    /// plain CLI/generic report with no explicit `--agent-key`, this defaults to the
    /// session's own id — i.e. by default every CLI-reported session is its own standalone
    /// agent, which preserves the CLI's original one-session-per-task behavior. This key is
    /// for internal grouping/equality only; see `title` for what to actually display.
    public var key: String

    /// The configured/custom display name, when one exists — e.g. OpenClaw's `identityName`
    /// ("Chief of Staff"), or a caller-supplied `--agent-name` ("Frontend Agent", "Atlas").
    /// This is the best available identity and should be preferred over everything else.
    public var displayName: String?

    /// A shorter technical name/slug, when distinct from `displayName` — e.g. OpenClaw's own
    /// agent id ("lead", "developer"). Used only if `displayName` is unavailable.
    public var name: String?

    /// A role/persona descriptor, when the integration distinguishes it from `displayName`.
    /// Currently unused by the OpenClaw adapter (OpenClaw doesn't expose a role distinct from
    /// `identityName` in what's locally verified) but modeled for integrations that do.
    public var role: String?

    public var provider: AgentProvider

    public init(key: String, displayName: String? = nil, name: String? = nil, role: String? = nil, provider: AgentProvider) {
        self.key = key
        self.displayName = displayName
        self.name = name
        self.role = role
        self.provider = provider
    }

    /// The PRIMARY title to show for this agent: configured display name → short name → role
    /// → provider, as a last resort. Deliberately does NOT fall back to `key` — for a
    /// default-derived key (the session's own id), showing a raw session identifier as the
    /// "agent name" would be worse than just naming the provider, which is at least a real,
    /// readable answer to "who is this."
    public var title: String {
        if let displayName, !displayName.trimmingCharacters(in: .whitespaces).isEmpty { return displayName }
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty { return name }
        if let role, !role.trimmingCharacters(in: .whitespaces).isEmpty { return role }
        return provider.displayName
    }

    /// Whichever of `role`/`provider` isn't already the title, for a secondary "role · project"
    /// style line. Returns nil when there's genuinely nothing more to say (title already used
    /// everything we know).
    public var secondaryDescriptor: String? {
        if let role, !role.trimmingCharacters(in: .whitespaces).isEmpty, role != title {
            return role
        }
        if provider.displayName != title {
            return provider.displayName
        }
        return nil
    }
}
