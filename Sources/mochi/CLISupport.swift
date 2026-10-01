import Foundation
import MochiCore

enum CLIError: Error, CustomStringConvertible {
    case invalidState(String)
    case invalidSource(String)
    case sessionNotFound(String)
    case writeFailed(String)

    var description: String {
        switch self {
        case .invalidState(let value):
            return "Unknown state '\(value)'. Valid states: \(CLISupport.knownStates.joined(separator: ", "))"
        case .invalidSource(let value):
            return "Unknown source '\(value)'. Valid sources: \(CLISupport.knownSources.joined(separator: ", "))"
        case .sessionNotFound(let id):
            return "No session found with id '\(id)'"
        case .writeFailed(let reason):
            return "Failed to write event: \(reason)"
        }
    }
}

enum CLISupport {
    // "stale"/"offline" are deliberately excluded: those are reconciliation's conclusions
    // about silence, never something a caller has standing to assert about itself (an agent
    // claiming "--state stale" would be fabricating the exact kind of certainty this field
    // doesn't have — see StaleDetector.reconcileLifecycle).
    static let knownStates = [
        "idle", "starting", "working", "thinking", "testing",
        "waiting", "needsPermission", "paused", "done", "error"
    ]

    static func validate(state: String?) throws -> String? {
        guard let state else { return nil }
        guard knownStates.contains(where: { $0.caseInsensitiveCompare(state) == .orderedSame }) else {
            throw CLIError.invalidState(state)
        }
        return state
    }

    // "demo" is deliberately excluded here too: it's set unconditionally by `mochi demo`
    // itself, never something a plain `mochi start` caller should be able to claim — a
    // script that could mark itself "demo" could just as easily *not*, which defeats the
    // point of demo data being structurally unable to pass as real.
    static let knownSources = ["openclaw", "claudeCode", "codex", "genericCLI", "passiveDiscovery"]

    static func validate(source: String?) throws -> String? {
        guard let source else { return nil }
        guard knownSources.contains(where: { $0.caseInsensitiveCompare(source) == .orderedSame }) else {
            throw CLIError.invalidSource(source)
        }
        return source
    }

    /// `mochi start` generates a short, readable session id when `--id` isn't given, so
    /// scripts can do `ID=$(mochi start ... )` without inventing their own uuid.
    static func generateAgentId(provider: String, project: String?) -> String {
        let projectSlug = (project ?? "session")
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let suffix = String(UUID().uuidString.prefix(6)).lowercased()
        let providerSlug = provider.lowercased()
        return "\(providerSlug)-\(projectSlug.isEmpty ? "session" : projectSlug)-\(suffix)"
    }

    static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = MochiDateCoding.jsonEncodingStrategy
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static func printJSON<T: Encodable>(_ value: T) {
        guard let data = try? jsonEncoder.encode(value), let string = String(data: data, encoding: .utf8) else {
            print("{}")
            return
        }
        print(string)
    }
}

/// Printable summary used by `list`/`inspect`/`demo` for plain-text output.
struct SessionSummaryLine {
    static func render(_ session: AgentSession) -> String {
        let elapsedText = formatDuration(session.elapsed)
        // The agent's own identity (e.g. "Chief of Staff"), not the provider that happens to
        // be running it — see AgentIdentity.title. The provider only shows up afterward, in
        // parens, when it's not already redundant with the title.
        var line = "\(session.displayName.padding(toLength: 16, withPad: " ", startingAt: 0)) "
        line += "\(session.status.friendlyLabel.padding(toLength: 12, withPad: " ", startingAt: 0)) "
        if let descriptor = session.agentIdentity.secondaryDescriptor { line += "(\(descriptor)) " }
        if let project = session.projectName { line += "\(project)  " }
        line += "· \(elapsedText)  [\(session.id)]"
        return line
    }

    static func formatDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 { return String(format: "%dh%02dm", hours, minutes) }
        if minutes > 0 { return String(format: "%dm%02ds", minutes, seconds) }
        return String(format: "%ds", seconds)
    }
}
