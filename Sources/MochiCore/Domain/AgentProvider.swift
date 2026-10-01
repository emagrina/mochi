import Foundation

/// Identifies what kind of tool/agent is reporting events. Not a closed set: any script can
/// send `provider: "my-tool"` and Mochi will render it with the generic Mochi variant.
public enum AgentProvider: Hashable, Sendable, Codable {
    case claude
    case codex
    case openclaw
    case generic(String)

    public var rawValue: String {
        switch self {
        case .claude: return "claude"
        case .codex: return "codex"
        case .openclaw: return "openclaw"
        case .generic(let name): return name
        }
    }

    public init(rawValue: String) {
        switch rawValue.lowercased() {
        case "claude", "claude-code", "claude_code": self = .claude
        case "codex": self = .codex
        case "openclaw": self = .openclaw
        default: self = .generic(rawValue)
        }
    }

    /// Display name shown in the UI.
    public var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .openclaw: return "OpenClaw"
        case .generic(let name): return name.isEmpty ? "Agent" : name
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
}
