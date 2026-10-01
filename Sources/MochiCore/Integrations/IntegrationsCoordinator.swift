import Foundation

/// Runs each enabled integration adapter's `pollOnce` on its own interval, forever, until
/// stopped. This is intentionally the *only* place that decides polling cadence — adapters
/// themselves don't know or care how often they're called.
///
/// Both intervals are deliberately slow (tens of seconds): these are supplementary signals
/// layered on top of the Mochi protocol, not the primary data path, so there's no reason to
/// burn CPU/battery polling them aggressively (product spec section 39).
@MainActor
public final class IntegrationsCoordinator {
    public struct AdapterEntry {
        public let adapter: IntegrationAdapter
        public let interval: TimeInterval
        public let isEnabled: @MainActor () -> Bool

        public init(adapter: IntegrationAdapter, interval: TimeInterval, isEnabled: @escaping @MainActor () -> Bool) {
            self.adapter = adapter
            self.interval = interval
            self.isEnabled = isEnabled
        }
    }

    private let entries: [AdapterEntry]
    private let writer: EventWriter
    private var tasks: [Task<Void, Never>] = []

    public init(entries: [AdapterEntry], writer: EventWriter = EventWriter()) {
        self.entries = entries
        self.writer = writer
    }

    public func start() {
        stop()
        for entry in entries {
            let task = Task { [writer] in
                while !Task.isCancelled {
                    if entry.isEnabled() {
                        await entry.adapter.pollOnce(into: writer)
                    }
                    try? await Task.sleep(nanoseconds: UInt64(entry.interval * 1_000_000_000))
                }
            }
            tasks.append(task)
        }
    }

    public func stop() {
        for task in tasks { task.cancel() }
        tasks.removeAll()
    }
}
