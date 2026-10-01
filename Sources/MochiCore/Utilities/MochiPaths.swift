import Foundation

/// Single source of truth for Mochi's on-disk layout under `~/.mochi`.
///
/// Layout (see docs/protocol.md for the full rationale):
///   ~/.mochi/inbox/        new event files, written atomically by any writer (CLI, adapters)
///   ~/.mochi/inbox/quarantine/   malformed events we couldn't parse, kept for `mochi doctor`
///   ~/.mochi/processed/    recently-ingested event files, retained briefly for debugging
///   ~/.mochi/state/        app-owned snapshot of session state + settings (single writer: the app)
///   ~/.mochi/logs/         optional debug logs
public struct MochiPaths: Sendable {
    public let root: URL

    public static let shared = MochiPaths()

    public init(root: URL? = nil) {
        if let root {
            self.root = root
        } else if let override = ProcessInfo.processInfo.environment["MOCHI_HOME"] {
            self.root = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            self.root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".mochi", isDirectory: true)
        }
    }

    public var inbox: URL { root.appendingPathComponent("inbox", isDirectory: true) }
    public var quarantine: URL { inbox.appendingPathComponent("quarantine", isDirectory: true) }
    public var processed: URL { root.appendingPathComponent("processed", isDirectory: true) }
    public var state: URL { root.appendingPathComponent("state", isDirectory: true) }
    public var logs: URL { root.appendingPathComponent("logs", isDirectory: true) }

    public var sessionsStateFile: URL { state.appendingPathComponent("sessions.json") }
    public var settingsFile: URL { state.appendingPathComponent("settings.json") }

    /// Creates every directory this layout needs. Safe to call repeatedly from both the CLI
    /// and the app; `FileManager.createDirectory` is idempotent when `withIntermediateDirectories`.
    @discardableResult
    public func ensureDirectoriesExist() -> Bool {
        let fm = FileManager.default
        let dirs = [inbox, quarantine, processed, state, logs]
        var ok = true
        for dir in dirs {
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                ok = false
            }
        }
        return ok
    }
}
