import Foundation
@testable import MochiCore

/// A fresh, isolated `~/.mochi`-equivalent directory per test, so tests never read or write
/// the real user data directory and never interfere with each other.
func makeTestPaths() -> MochiPaths {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("mochi-tests-\(UUID().uuidString)", isDirectory: true)
    let paths = MochiPaths(root: root)
    paths.ensureDirectoriesExist()
    return paths
}

func makeEvent(
    event: MochiEvent.Kind = .status,
    agentId: String = "agent-1",
    provider: String? = "claude",
    status: String? = "working",
    message: String? = nil,
    attentionReason: String? = nil,
    timestamp: Date = Date()
) -> MochiEvent {
    MochiEvent(event: event, agentId: agentId, provider: provider, status: status, message: message, attentionReason: attentionReason, timestamp: timestamp)
}
