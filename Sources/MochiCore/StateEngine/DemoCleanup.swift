import Foundation

/// Explicit, on-demand removal of demo data — `mochi demo --cleanup`.
///
/// This is deliberately narrow: it only ever touches sessions whose `source == .demo`,
/// determined by replaying real event data (the same path `mochi list`/`inspect` use), never
/// by matching a project name, agent name, or id pattern. A real session named anything a
/// demo scenario happens to also use is never at risk — see `SessionSource`'s doc comment for
/// the incident that made this distinction necessary in the first place.
///
/// Automatic expiry (`StaleDetector.demoRetention`, applied by `reconcileLifecycle`) already
/// makes demo sessions vanish from view on their own after a couple of minutes — this exists
/// for "I want it gone right now," particularly when the app isn't running to do that sweep.
public enum DemoCleanup {
    public struct Result: Sendable, Equatable {
        public var removedSessionCount: Int
        public var removedFileCount: Int
    }

    @discardableResult
    public static func removeAllDemoData(paths: MochiPaths = .shared) -> Result {
        let projection = SessionProjection.replayAll(paths: paths)
        let demoIDs = Set(projection.sessions.values.filter { $0.source == .demo }.map(\.id))
        guard !demoIDs.isEmpty else { return Result(removedSessionCount: 0, removedFileCount: 0) }

        let fm = FileManager.default
        var removedFiles = 0
        for dir in [paths.inbox, paths.processed] {
            guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for url in entries where url.pathExtension == "json" && !url.lastPathComponent.hasPrefix(".") {
                guard let data = try? Data(contentsOf: url), let event = try? MochiEvent.decode(data) else { continue }
                if demoIDs.contains(event.agentId) {
                    try? fm.removeItem(at: url)
                    removedFiles += 1
                }
            }
        }

        // The app's own persisted snapshot (if any) needs the same filter, or a currently-
        // stopped Mochi.app would still show the just-deleted sessions on its next launch —
        // replaying the now-empty event files wouldn't resurrect them, but the snapshot is a
        // separate cache of the last-known state and has to be cleaned independently.
        let store = PersistenceStore(paths: paths)
        let remainingSnapshot = store.loadSessionSnapshot().filter { !demoIDs.contains($0.id) }
        store.saveSessionSnapshot(remainingSnapshot)

        return Result(removedSessionCount: demoIDs.count, removedFileCount: removedFiles)
    }
}
