import Foundation
#if canImport(Dispatch)
import Dispatch
#endif

/// Watches `~/.mochi/inbox` for new event files and yields decoded `MochiEvent`s in
/// timestamp order, one at a time, as an `AsyncStream`.
///
/// Design notes (see docs/protocol.md "Concurrency" section):
/// - We use a `DispatchSource` filesystem watch on the directory itself rather than polling,
///   so Mochi does zero work while idle (product spec section 39: no aggressive polling).
/// - Every notification triggers a *drain*, not an incremental read: we list the directory,
///   sort by filename (which is timestamp-prefixed), and process everything we haven't seen.
///   This makes the watcher resilient to missed/coalesced filesystem events, and means a
///   cold start (app wasn't running when events arrived) just drains the whole backlog.
/// - Malformed JSON is quarantined, not dropped silently and not fatal to the app.
/// - Successfully processed files are moved to `processed/`, bounded to `processedRetention`
///   most-recent files so disk usage never grows unbounded.
public actor EventInbox {
    public struct QuarantinedEvent: Sendable {
        public let url: URL
        public let reason: String
    }

    private let paths: MochiPaths
    private let processedRetention: Int
    private var watcherSource: DispatchSourceFileSystemObject?
    private var watchedDescriptor: Int32 = -1
    private var continuation: AsyncStream<MochiEvent>.Continuation?
    private var quarantineContinuation: AsyncStream<QuarantinedEvent>.Continuation?

    public init(paths: MochiPaths = .shared, processedRetention: Int = 500) {
        self.paths = paths
        self.processedRetention = processedRetention
    }

    /// Stream of successfully decoded, validated events, oldest first within each drain.
    public func events() -> AsyncStream<MochiEvent> {
        // The closure literal below inherits this method's actor isolation (we're already
        // on the EventInbox actor), so this can call straight through with no Task/await hop.
        AsyncStream { continuation in
            self.setEventsContinuation(continuation)
        }
    }

    /// Stream of events we could not parse/validate, for `mochi doctor` and Settings > Advanced.
    public func quarantinedEvents() -> AsyncStream<QuarantinedEvent> {
        AsyncStream { continuation in
            self.setQuarantineContinuation(continuation)
        }
    }

    private func setEventsContinuation(_ c: AsyncStream<MochiEvent>.Continuation) {
        continuation = c
        startWatchingIfNeeded()
        drain()
    }

    private func setQuarantineContinuation(_ c: AsyncStream<QuarantinedEvent>.Continuation) {
        quarantineContinuation = c
    }

    private func startWatchingIfNeeded() {
        guard watcherSource == nil else { return }
        paths.ensureDirectoriesExist()
        let fd = open(paths.inbox.path, O_EVTONLY)
        guard fd >= 0 else { return }
        watchedDescriptor = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename],
            queue: DispatchQueue(label: "mochi.event-inbox.watch")
        )
        source.setEventHandler { [weak self] in
            Task { await self?.drain() }
        }
        source.setCancelHandler { [fd] in close(fd) }
        source.resume()
        watcherSource = source
    }

    /// Reads every pending file in the inbox (oldest first), decodes it, and either yields it
    /// or quarantines it. Safe to call concurrently with itself; actor isolation serializes it.
    public func drain() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: paths.inbox, includingPropertiesForKeys: nil) else { return }
        let pending = entries
            .filter { $0.pathExtension == "json" && !$0.lastPathComponent.hasPrefix(".") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !pending.isEmpty else { return }

        for url in pending {
            guard let data = try? Data(contentsOf: url) else { continue }
            do {
                let event = try MochiEvent.decode(data)
                try event.validate()
                // Archive before yielding: a consumer can react to a yielded event (and
                // inspect the filesystem) on another thread the instant it's yielded, so the
                // file must already be out of the inbox by then, not "about to move."
                moveToProcessed(url)
                continuation?.yield(event)
            } catch {
                quarantine(url, reason: String(describing: error))
            }
        }
        pruneProcessed()
    }

    private func moveToProcessed(_ url: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: paths.processed, withIntermediateDirectories: true)
        let destination = paths.processed.appendingPathComponent(url.lastPathComponent)
        try? fm.removeItem(at: destination)
        try? fm.moveItem(at: url, to: destination)
    }

    private func quarantine(_ url: URL, reason: String) {
        let fm = FileManager.default
        try? fm.createDirectory(at: paths.quarantine, withIntermediateDirectories: true)
        let destination = paths.quarantine.appendingPathComponent(url.lastPathComponent)
        try? fm.removeItem(at: destination)
        try? fm.moveItem(at: url, to: destination)
        quarantineContinuation?.yield(QuarantinedEvent(url: destination, reason: reason))
    }

    private func pruneProcessed() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: paths.processed, includingPropertiesForKeys: nil) else { return }
        guard entries.count > processedRetention else { return }
        let sorted = entries.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let toDelete = sorted.prefix(sorted.count - processedRetention)
        for url in toDelete {
            try? fm.removeItem(at: url)
        }
    }

    public func stopWatching() {
        watcherSource?.cancel()
        watcherSource = nil
    }
}
