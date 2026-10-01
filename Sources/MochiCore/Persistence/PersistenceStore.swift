import Foundation

/// Loads/saves `MochiSettings` and the session snapshot. Both are plain JSON files written
/// via `AtomicFile`, owned exclusively by the app process (the CLI never writes here — it
/// only ever writes events into the inbox), so there's no multi-writer concern for these two
/// files the way there is for the inbox.
public struct PersistenceStore: Sendable {
    public let paths: MochiPaths

    public init(paths: MochiPaths = .shared) {
        self.paths = paths
    }

    public func loadSettings() -> MochiSettings {
        guard let data = try? Data(contentsOf: paths.settingsFile) else { return .default }
        let decoder = JSONDecoder()
        return (try? decoder.decode(MochiSettings.self, from: data)) ?? .default
    }

    public func save(_ settings: MochiSettings) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(settings) else { return }
        try? AtomicFile.write(data, to: paths.settingsFile)
    }

    /// Snapshot of live sessions, saved periodically by the app so a restart doesn't lose
    /// `attentionNotified` bookkeeping or recently-pruned history before the next replay.
    public func loadSessionSnapshot() -> [AgentSession] {
        guard let data = try? Data(contentsOf: paths.sessionsStateFile) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = MochiDateCoding.jsonDecodingStrategy
        return (try? decoder.decode([AgentSession].self, from: data)) ?? []
    }

    public func saveSessionSnapshot(_ sessions: [AgentSession]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = MochiDateCoding.jsonEncodingStrategy
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(sessions) else { return }
        try? AtomicFile.write(data, to: paths.sessionsStateFile)
    }
}
