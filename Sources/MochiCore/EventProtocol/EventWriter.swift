import Foundation

/// Writes a `MochiEvent` into the inbox. This is the only thing the CLI and any future
/// adapter need to know about to talk to Mochi — no socket, no daemon, no server.
public struct EventWriter: Sendable {
    public let paths: MochiPaths

    public init(paths: MochiPaths = .shared) {
        self.paths = paths
    }

    @discardableResult
    public func write(_ event: MochiEvent) throws -> URL {
        try event.validate()
        paths.ensureDirectoriesExist()
        let data = try event.encoded()
        // Filename is sortable by time so a cold-started app can replay the backlog in order.
        let prefix = MochiDateCoding.filenameSafeString(from: event.timestamp)
        return try AtomicFile.writeUnique(data, directory: paths.inbox, prefix: prefix)
    }
}
