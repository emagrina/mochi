import Foundation

/// Rebuilds session state by replaying every event on disk (`processed/` then any
/// not-yet-ingested `inbox/` files) through `SessionReducer`.
///
/// This is what the CLI's `list`/`inspect`/`doctor` commands use: they are short-lived
/// processes with no running state engine, but Mochi must stay useful even if `Mochi.app`
/// isn't running (product spec section 6), so "replay everything" is the read path rather
/// than depending on the app's own snapshot file.
public enum SessionProjection {
    public struct Result: Sendable {
        public var sessions: [String: AgentSession]
        public var malformedCount: Int
    }

    public static func replayAll(paths: MochiPaths = .shared) -> Result {
        paths.ensureDirectoriesExist()
        let fm = FileManager.default
        var urls: [URL] = []
        for dir in [paths.processed, paths.inbox] {
            if let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                urls.append(contentsOf: entries.filter { $0.pathExtension == "json" && !$0.lastPathComponent.hasPrefix(".") })
            }
        }
        urls.sort { $0.lastPathComponent < $1.lastPathComponent }

        var sessions: [String: AgentSession] = [:]
        var malformed = 0
        for url in urls {
            guard let data = try? Data(contentsOf: url) else { malformed += 1; continue }
            do {
                let event = try MochiEvent.decode(data)
                try event.validate()
                SessionReducer.apply(event, to: &sessions)
            } catch {
                malformed += 1
            }
        }
        // Raw replay only knows what each event claimed at the time; a session can still be
        // sitting on a "working" status from hours ago with nothing since. Reconciling here
        // — not just in the live app — is what makes `mochi list`/`inspect`/`doctor` truthful
        // even when run standalone, with Mochi.app not running to do it for them.
        StaleDetector.reconcileLifecycle(&sessions, now: Date())
        return Result(sessions: sessions, malformedCount: malformed)
    }
}
