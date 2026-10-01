import SwiftUI
import MochiCore

/// One line in the popover list. Deliberately plain — spacing and typography carry the
/// hierarchy instead of a bordered card (product spec section 43).
struct AgentRow: View {
    let session: AgentSession
    let now: Date
    let reducedMotion: Bool

    var body: some View {
        HStack(spacing: 10) {
            MochiAvatar(status: session.status, provider: session.provider, size: 32, reducedMotion: reducedMotion)

            VStack(alignment: .leading, spacing: 2) {
                // The agent's own identity is the strongest text in the row — who is doing
                // the work, not which runtime happens to be running it. See
                // AgentIdentity.title and docs/architecture.md's "Agent vs. session identity."
                HStack(spacing: 4) {
                    Text(session.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if session.discovery == .detected {
                        Text("· detected")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                // Secondary: role/provider and project/session-context — e.g. "Developer ·
                // Aenari" or "OpenClaw · Dashboard session". This is what lets two rows for
                // the same agent (two sessions) read as distinguishable rather than as an
                // ambiguous duplicate.
                if let context = contextLine {
                    Text(context)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 2) {
                StatusBadge(status: session.status)
                if session.discovery == .instrumented {
                    Text(elapsedText)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var contextLine: String? {
        let parts = [session.agentIdentity.secondaryDescriptor, session.projectName].compactMap { $0 }
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
        let isStale = StaleDetector.isStale(session, now: now)
        if isStale {
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

/// A small pill that pairs an icon (never color alone) with the friendly status label.
struct StatusBadge: View {
    let status: AgentStatus

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbolName)
                .font(.system(size: 9, weight: .bold))
            Text(status.friendlyLabel)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(tint)
    }

    private var symbolName: String {
        switch status {
        case .idle: return "moon.zzz.fill"
        case .starting: return "sparkles"
        case .working: return "hammer.fill"
        case .thinking: return "ellipsis.bubble.fill"
        case .testing: return "checkmark.seal.fill"
        case .waiting: return "hourglass"
        case .needsPermission: return "exclamationmark.triangle.fill"
        case .paused: return "pause.fill"
        case .done: return "checkmark.circle.fill"
        case .error: return "xmark.octagon.fill"
        case .offline: return "power"
        case .custom: return "questionmark.circle.fill"
        }
    }

    private var tint: Color {
        switch status {
        case .needsPermission: return MochiColors.attention
        case .error: return MochiColors.errorTint
        case .done: return MochiColors.successTint
        default: return .secondary
        }
    }
}
