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
                    infoGrid
                    actions
                    if !session.recentActivity.isEmpty {
                        activityLog
                    }
                }
            }
            .padding(16)
        }
        .frame(width: 340)
    }

    private var header: some View {
        HStack(spacing: 12) {
            MochiAvatar(status: session.status, provider: session.provider, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayName).font(.headline)
                let context = [session.agentIdentity.secondaryDescriptor, session.projectName].compactMap { $0 }.joined(separator: " · ")
                if !context.isEmpty {
                    Text(context).font(.subheadline).foregroundStyle(.secondary)
                }
                StatusBadge(status: session.status)
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
            row("Provider", session.provider.displayName)
            if let task = session.currentTask { row("Task", task) }
            if let activity = session.currentActivity { row("Activity", activity) }
            row("Started", session.startedAt.formatted(date: .abbreviated, time: .shortened))
            if let finished = session.finishedAt {
                row("Finished", finished.formatted(date: .abbreviated, time: .shortened))
            } else {
                row("Last active", relativeString(session.lastActivityAt))
            }
            row("Elapsed", AgentRow.shortDuration(session.elapsed))
            if StaleDetector.isStale(session, now: now) {
                row("Note", "Quiet for a while — may have stopped without telling Mochi.")
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
