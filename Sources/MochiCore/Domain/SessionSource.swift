import Foundation

/// WHERE a session's events came from — distinct from `AgentProvider` (which runtime is
/// executing the work) and from `AgentIdentity` (who is doing the work). This is what makes
/// demo data structurally impossible to confuse with a real agent, and what a future
/// reconciliation pass uses to decide how (or whether) it can verify a session is still alive.
///
/// This exists because of a real incident: `mochi demo` sessions persisted from earlier
/// development testing were still showing up — as "Working" — in a normal `open Mochi.app`
/// launch days later, indistinguishable from real OpenClaw sessions except by reading their
/// project names. Filtering by name was explicitly ruled out (a real project could be named
/// anything a demo scenario happens to also use); provenance has to be tracked as data, not
/// inferred from strings a human would recognize.
public enum SessionSource: Hashable, Sendable, Codable {
    /// OpenClaw's own session store, via `OpenClawAdapter`'s polling.
    case openClaw
    /// The Claude Code hook script (`Integrations/ClaudeCode/mochi-claude-hook.sh`), which
    /// opts into this explicitly via `--source claudeCode` — Mochi has no way to verify a
    /// plain CLI call actually came from Claude Code's hook system, so this is only ever set
    /// when the caller says so, never inferred from `provider`.
    case claudeCode
    /// Same idea as `claudeCode`, for a future Codex wrapper that opts in with `--source
    /// codex`. Nothing emits this yet — Codex is detection-only today (see
    /// `docs/integrations.md`) — but the protocol and domain model already support it.
    case codex
    /// A plain `mochi` CLI call with no more specific source given. This is the default for
    /// `mochi start`/`status`/etc. — Mochi knows with certainty an event arrived through its
    /// own CLI, which is itself real provenance, just not a named integration.
    case genericCLI
    /// `mochi demo`. Always true — `DemoCommand` tags every event it writes with this
    /// unconditionally; there is no way to make a demo session claim to be anything else.
    case demo
    /// `ProcessDiscoveryAdapter` noticed a matching process exists. See `DiscoveryKind` — a
    /// session with this source is always also `discovery == .detected`, never promoted to
    /// looking like a real instrumented session.
    case passiveDiscovery
    /// No source field on the event, or one we don't recognize. This is the honest default
    /// for data written before this field existed, or by a raw hand-written event file —
    /// never auto-upgraded to a trusted source, never destructively deleted by anything that
    /// operates on a specific known source (see `mochi demo --cleanup`, which only ever
    /// touches `.demo`).
    case unknown

    public var rawValue: String {
        switch self {
        case .openClaw: return "openclaw"
        case .claudeCode: return "claudeCode"
        case .codex: return "codex"
        case .genericCLI: return "genericCLI"
        case .demo: return "demo"
        case .passiveDiscovery: return "passiveDiscovery"
        case .unknown: return "unknown"
        }
    }

    public init(rawValue: String) {
        switch rawValue {
        case "openclaw", "openClaw": self = .openClaw
        case "claudeCode", "claude-code": self = .claudeCode
        case "codex": self = .codex
        case "genericCLI", "generic-cli", "cli": self = .genericCLI
        case "demo": self = .demo
        case "passiveDiscovery", "passive-discovery", "detected": self = .passiveDiscovery
        default: self = .unknown
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// Whether this source is something Mochi can actively re-verify ("is this session still
    /// really there?") by asking an integration again, as opposed to only ever hearing about
    /// it passively. Drives whether a quiet session should be treated as merely stale (we
    /// just haven't heard from it) or something reconciliation can get a real answer about.
    public var isReconcilable: Bool {
        switch self {
        case .openClaw: return true
        case .claudeCode, .codex, .genericCLI, .demo, .passiveDiscovery, .unknown: return false
        }
    }
}
