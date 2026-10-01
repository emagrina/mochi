import Foundation

/// Passive supplementary signal: "a process matching a known agent CLI is running."
///
/// This deliberately never claims more than that. A detected session always renders as
/// `DiscoveryKind.detected` ("Detected — no activity information available"), never with a
/// task, activity, or fine-grained status, because we have zero evidence for any of those
/// (product spec section 10). It exists purely so an agent the user hasn't wired up to the
/// Mochi protocol yet still shows up as *something*, nudging them toward real instrumentation.
public struct ProcessDiscoveryAdapter: IntegrationAdapter {
    public let id = "process-discovery"
    public let displayName = "Process Detection"
    public let reliability: IntegrationReliability = .detectionOnly

    /// Exact (case-insensitive) basename matches only — no substring matching — to avoid
    /// false positives from unrelated binaries that happen to contain "claude" or "codex".
    private static let knownBinaryNames: [String: String] = [
        "claude": "claude",
        "codex": "codex",
        "openclaw": "openclaw"
    ]

    public init() {}

    public func currentStatus() async -> IntegrationStatus { .connected }

    public func pollOnce(into writer: EventWriter) async {
        let result = await ProcessRunner.run("ps", ["-axo", "pid=,comm="], timeout: 3)
        guard result.exitCode == 0, let output = String(data: result.stdout, encoding: .utf8) else { return }

        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let spaceIndex = trimmed.firstIndex(of: " ") else { continue }
            let pidString = trimmed[trimmed.startIndex..<spaceIndex]
            let commandPath = trimmed[trimmed.index(after: spaceIndex)...].trimmingCharacters(in: .whitespaces)
            let basename = (commandPath as NSString).lastPathComponent.lowercased()
            guard let provider = Self.knownBinaryNames[basename], let pid = Int32(pidString) else { continue }

            let event = MochiEvent(
                event: .status,
                agentId: "detected:\(provider):\(pid)",
                provider: provider,
                source: SessionSource.passiveDiscovery.rawValue,
                status: AgentStatus.idle.rawValue,
                message: nil,
                pid: pid,
                metadata: ["mochi.discoveryKind": "detected"],
                timestamp: Date()
            )
            _ = try? writer.write(event)
        }
    }
}
