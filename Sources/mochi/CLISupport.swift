import Foundation
import MochiCore

enum CLIError: Error, CustomStringConvertible {
    case invalidState(String)
    case sessionNotFound(String)
    case writeFailed(String)

    var description: String {
        switch self {
        case .invalidState(let value):
            return "Unknown state '\(value)'. Valid states: \(CLISupport.knownStates.joined(separator: ", "))"
        case .sessionNotFound(let id):
            return "No session found with id '\(id)'"
        case .writeFailed(let reason):
            return "Failed to write event: \(reason)"
        }
    }
}

enum CLISupport {
    static let knownStates = [
        "idle", "starting", "working", "thinking", "testing",
        "waiting", "needsPermission", "paused", "done", "error", "offline"
    ]

    static func validate(state: String?) throws -> String? {
        guard let state else { return nil }
        guard knownStates.contains(where: { $0.caseInsensitiveCompare(state) == .orderedSame }) else {
            throw CLIError.invalidState(state)
        }
        return state
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
        var line = "\(session.provider.displayName.padding(toLength: 8, withPad: " ", startingAt: 0)) "
        line += "\(session.status.friendlyLabel.padding(toLength: 12, withPad: " ", startingAt: 0)) "
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
