import SwiftUI
import MochiCore

/// One agent, as its own soft rounded card — reference.png's card language, implemented
/// natively (a filled `RoundedRectangle` surface sitting on the popover's own
/// `.regularMaterial` background, not a web-style box-shadow card). Replaces the earlier flat
/// `AgentRow`.
struct AgentCard: View {
    let session: AgentSession
    let now: Date
    let reducedMotion: Bool
    var isHovered: Bool = false

    static let cardHeight: CGFloat = 82
    static let cardSpacing: CGFloat = 12
    static let cornerRadius: CGFloat = 26

    var body: some View {
        HStack(spacing: 12) {
            MochiAvatar(status: session.status, identityKey: session.agentIdentity.key, size: 52, reducedMotion: reducedMotion)

            VStack(alignment: .leading, spacing: 3) {
                // The agent's own identity is the strongest text in the card — who is doing
                // the work, not which runtime happens to be running it. See
                // AgentIdentity.title and docs/architecture.md's "Agent vs. session identity."
                HStack(spacing: 4) {
                    // The name is the PRIMARY identity (never the provider — see
                    // AgentIdentity.title) and must never be what gives way on a tight
                    // row — a fixed-width icon badge, not variable-width text, is what keeps
                    // a longer name like "Chief of Staff" from being what truncates.
                    Text(session.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                        .layoutPriority(1)
                    if session.discovery == .detected {
                        Image(systemName: "eye")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .help("Detected — no activity information available")
                            .accessibilityLabel("detected")
                    }
                }
                if let context = contextLine {
                    Text(context)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary.opacity(0.85))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 7) {
                StatusPill(status: session.status)
                if session.discovery == .instrumented {
                    Text(elapsedText)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }

            chevron
        }
        .padding(.horizontal, 16)
        .frame(height: Self.cardHeight)
        .background(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(MochiColors.cardSurface)
        )
        .compositingGroup()
        .shadow(color: MochiColors.cardShadow, radius: 8, y: 3)
        .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 26, height: 26)
            .background(Circle().fill(isHovered ? MochiColors.chipSurfaceHover : MochiColors.chipSurface))
    }

    // Demo provenance is demoted to a plain suffix on the secondary line (e.g.
    // "Huginn · Demo") rather than a bright badge beside the name — the name stays the
    // strongest thing in the card, and "demo" is useful-but-quiet context, not a warning.
    private var contextLine: String? {
        var parts = [session.agentIdentity.secondaryDescriptor, session.projectName].compactMap { $0 }
        if session.source == .demo { parts.append("Demo") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var subtitle: String {
        if session.discovery == .detected {
            return "No activity information available"
        }
        if let activity = session.currentActivity { return activity }
        if let task = session.currentTask { return task }
        if let attentionMessage = session.attentionMessage { return attentionMessage }
        if let error = session.errorMessage { return error }
        return session.status.friendlyLabel
    }

    private var elapsedText: String {
        // `.stale`/`.offline` are reconciled status values, not a display-only heuristic —
        // see `StaleDetector.reconcileLifecycle`. "Last seen" vs. an elapsed duration is the
        // whole point: they mean different things and must never look alike.
        if session.status == .stale || session.status == .offline {
            return "Last seen \(Self.shortDuration(now.timeIntervalSince(session.lastActivityAt))) ago"
        }
        // "2m ago" (time since it finished) rather than "14m" (how long the task took) — a
        // completed session showing an elapsed-looking duration reads too much like an
        // active one; "ago" is the unambiguous "this is done" signal.
        if let finishedAt = session.finishedAt {
            return "\(Self.shortDuration(now.timeIntervalSince(finishedAt))) ago"
        }
        return Self.shortDuration(now.timeIntervalSince(session.startedAt))
    }

    private var accessibilityLabel: String {
        var parts = [session.displayName]
        if session.source == .demo { parts.append("demo session") }
        if let context = contextLine { parts.append(context) }
        parts.append(contentsOf: [session.status.friendlyLabel, subtitle, elapsedText])
        return parts.joined(separator: ", ")
    }

    static func shortDuration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let hours = total / 3600, minutes = (total % 3600) / 60, seconds = total % 60
        if hours > 0 { return "\(hours)h\(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(seconds)s"
    }
}
