import SwiftUI
import MochiCore

struct AgentDetailView: View {
    let session: AgentSession
    let now: Date

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if session.discovery == .detected {
                    detectedNotice
                } else {
                    card { infoGrid }
                    actions
                    if !session.recentActivity.isEmpty {
                        card { activityLog }
                    }
                }
            }
            .padding(16)
        }
        .frame(width: 400, height: 520)
    }

    /// The same soft rounded surface `AgentCard` uses, reused here for visual consistency
    /// with the popover's card language rather than a plain flat list.
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(MochiColors.cardSurface))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(MochiColors.cardBorder, lineWidth: 1))
    }

    private var header: some View {
        HStack(spacing: 12) {
            MochiAvatar(status: session.status, identityKey: session.agentIdentity.key, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(session.displayName).font(.headline)
                    if session.source == .demo {
                        Text("· Demo")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(MochiColors.attention)
                    }
                }
                let context = [session.agentIdentity.secondaryDescriptor, session.projectName].compactMap { $0 }.joined(separator: " · ")
                if !context.isEmpty {
                    Text(context).font(.subheadline).foregroundStyle(.secondary)
                }
                StatusPill(status: session.status)
            }
            Spacer()
        }
    }

    private var detectedNotice: some View {
        Text("A \(session.displayName) process is running, but it hasn't been instrumented with the Mochi protocol, so no activity details are available. See the Integrations tab in Settings to wire it up.")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
    }

    private var infoGrid: some View {
        VStack(alignment: .leading, spacing: 6) {
            row("Source", sourceLabel)
            row("Provider", session.provider.displayName)
            row("Agent key", session.agentIdentity.key)
            if let task = session.currentTask { row("Task", task) }
            if let activity = session.currentActivity { row("Activity", activity) }
            row("Started", session.startedAt.formatted(date: .abbreviated, time: .shortened))
            if let finished = session.finishedAt {
                row("Finished", finished.formatted(date: .abbreviated, time: .shortened))
            } else if session.status == .stale || session.status == .offline {
                row("Last seen", relativeString(session.lastActivityAt))
            } else {
                row("Last active", relativeString(session.lastActivityAt))
            }
            row("Elapsed", AgentCard.shortDuration(session.elapsed))
            if session.status == .stale {
                row("Note", "Quiet for a while — Mochi can no longer confirm this is still running.")
            } else if session.status == .offline {
                row("Note", "No activity for a long time — presumed to have stopped without telling Mochi.")
            }
            if let pid = session.pid {
                row("Process", "PID \(pid) · \(StaleDetector.isProcessAlive(pid: pid) ? "running" : "not running")")
            }
            if let branch = session.branch { row("Branch", branch) }
            if let sessionId = session.sessionId { row("Session", sessionId) }
            row("Session ID", session.id)
            if let path = session.projectPath { row("Path", path) }
            if let reason = session.attentionReason { row("Needs you", reason.friendlyLabel) }
            if let attentionMessage = session.attentionMessage { row("Message", attentionMessage) }
            if let error = session.errorMessage { row("Error", error) }
            if let pr = session.pullRequest {
                row("Pull request", pr.title ?? pr.url ?? "#\(pr.number.map(String.init) ?? "")")
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private var actions: some View {
        FlowActions {
            if AgentActions.canOpenProject(session) {
                actionButton("Open Project", "folder") { AgentActions.openProjectInFinder(session) }
            }
            if AgentActions.canOpenTerminal(session) {
                actionButton("Open Terminal", "terminal") { AgentActions.openTerminal(session) }
            }
            if AgentActions.canOpenPullRequest(session) {
                actionButton("Open Pull Request", "arrow.up.right.square") { AgentActions.openPullRequest(session) }
            }
            actionButton("Copy Session ID", "doc.on.doc") { AgentActions.copySessionID(session) }
            if session.projectPath != nil {
                actionButton("Copy Path", "doc.on.doc") { AgentActions.copyProjectPath(session) }
            }
        }
    }

    private func actionButton(_ title: String, _ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11.5))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var activityLog: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent activity").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            ForEach(session.recentActivity.reversed().prefix(20)) { entry in
                HStack(alignment: .top, spacing: 8) {
                    Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .frame(width: 60, alignment: .leading)
                    Text(entry.message)
                        .font(.system(size: 11.5))
                }
            }
        }
    }

    private func relativeString(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named))
    }

    private var sourceLabel: String {
        switch session.source {
        case .openClaw: return "OpenClaw"
        case .claudeCode: return "Claude Code"
        case .codex: return "Codex"
        case .genericCLI: return "mochi CLI"
        case .demo: return "Demo (mochi demo)"
        case .passiveDiscovery: return "Process detection"
        case .unknown: return "Unknown (predates source tracking)"
        }
    }
}

/// A trivial flow layout for action buttons so they wrap instead of overflowing at the
/// popover's fixed width.
private struct FlowActions<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Actions").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            WrapHStack {
                content
            }
        }
    }
}

private struct WrapHStack: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 300
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + 6
                rowHeight = 0
            }
            x += size.width + 6
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + 6
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + 6
            rowHeight = max(rowHeight, size.height)
        }
    }
}
