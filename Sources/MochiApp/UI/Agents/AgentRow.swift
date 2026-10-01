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
                HStack(spacing: 4) {
                    Text(session.displayName)
                        .font(.system(size: 13, weight: .semibold))
                    if session.discovery == .detected {
                        Text("· detected")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                if let project = session.projectName {
                    Text(project)
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
        return Self.shortDuration(session.finishedAt.map { $0.timeIntervalSince(session.startedAt) } ?? now.timeIntervalSince(session.startedAt))
    }

    private var accessibilityLabel: String {
        "\(session.displayName), \(session.projectName ?? "project unknown"), \(session.status.friendlyLabel), \(subtitle), \(elapsedText)"
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
