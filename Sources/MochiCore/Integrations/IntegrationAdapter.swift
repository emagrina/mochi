import Foundation

/// How trustworthy/complete an integration's output is. Shown verbatim in Settings so the
/// user never mistakes a heuristic for a certainty (product spec sections 9, 53).
public enum IntegrationReliability: String, Sendable, Codable {
    /// A first-party, documented mechanism (a CLI flag, a hook API) that we've verified
    /// against the locally installed tool.
    case supported
    /// Built on a real signal, but one that requires inference to map onto Mochi's states
    /// (e.g. "last updated 40s ago" → "probably working").
    case heuristic
    /// Works today but depends on behavior/JSON shapes we could only partially verify
    /// locally; treat as best-effort and expect it to need adjustment.
    case experimental
    /// We can see a process exists and nothing more.
    case detectionOnly
}

public enum IntegrationStatus: Sendable, Equatable {
    case connected
    case notConfigured
    case unavailable(String)
}

/// Common shape for anything that turns a third-party tool's state into Mochi protocol
/// events. `MochiCore` depends on this protocol, never on a concrete adapter, which is what
/// keeps the OpenClaw adapter (or a future Codex one) swappable/removable without touching
/// the state engine (product spec section 8: "Mochi's core MUST NOT depend on OpenClaw").
public protocol IntegrationAdapter: Sendable {
    var id: String { get }
    var displayName: String { get }
    var reliability: IntegrationReliability { get }

    func currentStatus() async -> IntegrationStatus

    /// Runs one polling/ingest cycle, writing any events it finds via `EventWriter`.
    /// Called periodically by `IntegrationsCoordinator`; adapters that are push-based
    /// instead of poll-based are free to make this a no-op and feed events some other way.
    func pollOnce(into writer: EventWriter) async
}
