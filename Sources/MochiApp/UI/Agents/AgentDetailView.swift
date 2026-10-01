import SwiftUI
import MochiCore

/// One agent's full detail — reached by tapping a card, left by tapping `backButton` (or
/// `⌘[`). `onBack` is a plain closure rather than this view reaching into `AppModel` itself:
/// `PopoverView` owns the one piece of navigation state (`AppModel.selectedSessionID`), this
/// view just reports "the user wants out."
struct AgentDetailView: View {
    let session: AgentSession
    let now: Date
    let reducedMotion: Bool
    let onBack: () -> Void

    /// Keeps the detail screen roughly the same overall height as the main list rather than
    /// growing to fit however much recent-activity history a long-running agent has
    /// accumulated — the fixed header sits above this, and this scrolls internally beyond it.
    private static let scrollAreaHeight: CGFloat = 440

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            detailHeader
            if session.discovery == .detected {
                detectedNotice
                    .padding(EdgeInsets(top: 0, leading: 20, bottom: 24, trailing: 20))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        card { infoGrid }
                        card { actions }
                        if !session.recentActivity.isEmpty {
                            card { activityLog }
                        }
                    }
                    // Trailing > leading on purpose: gives the scrollbar room of its own
                    // instead of letting it overlap the cards' rounded right edge.
                    .padding(EdgeInsets(top: 4, leading: 20, bottom: 20, trailing: 22))
                }
                .frame(height: Self.scrollAreaHeight)
            }
        }
    }

    // MARK: - Header

    private var detailHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            backButton
            MochiAvatar(status: session.status, identityKey: session.agentIdentity.key, size: 48, reducedMotion: reducedMotion)
            VStack(alignment: .leading, spacing: 3) {
                Text(session.displayName)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                if let context = contextLine {
                    Text(context)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                StatusPill(status: session.status)
            }
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 20, leading: 20, bottom: 16, trailing: 18))
    }

    /// Small, rounded, material-backed — the same visual family as the main header's settings
    /// gear and each card's chevron, not a traditional toolbar/title-bar back control. `⌘[` is
    /// supported as a bonus for anyone who already reaches for it; the button itself is what
    /// the product spec requires, since nobody should have to know a shortcut exists.
    private var backButton: some View {
        Button(action: onBack) {
            Image(systemName: "chevron.left")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(MochiColors.chipSurface))
        }
        .buttonStyle(.plain)
        .keyboardShortcut("[", modifiers: .command)
        .help("Back to agent list")
        .accessibilityLabel("Back")
    }

    /// Demo provenance folds into this line rather than sitting beside the name as its own
    /// badge — same treatment `AgentCard` uses, for consistency between the list and detail.
    private var contextLine: String? {
        var parts = [session.agentIdentity.secondaryDescriptor, session.projectName].compactMap { $0 }
        if session.source == .demo { parts.append("Demo") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var detectedNotice: some View {
        Text("A \(session.displayName) process is running, but it hasn't been instrumented with the Mochi protocol, so no activity details are available. See the Integrations tab in Settings to wire it up.")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Cards

    /// The same soft rounded surface `AgentCard` uses, reused here for visual consistency
    /// with the popover's card language — material and shadow carry the separation, not a
    /// stroke (see `MochiColors.cardSurface`). `.frame(maxWidth: .infinity)` is what makes
    /// every card (info, actions, activity) span the same width instead of shrinking to fit
    /// whatever its shortest row happens to be.
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(MochiColors.cardSurface))
    }

    private var infoGrid: some View {
        VStack(alignment: .leading, spacing: 7) {
            row("Source", sourceLabel)
            row("Provider", session.provider.displayName)
            row("Agent key", session.agentIdentity.key, monospaced: true)
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
            if let sessionId = session.sessionId { row("Session", sessionId, monospaced: true) }
            row("Session ID", session.id, monospaced: true)
            if let path = session.projectPath { row("Path", path, monospaced: true) }
            if let reason = session.attentionReason { row("Needs you", reason.friendlyLabel) }
            if let attentionMessage = session.attentionMessage { row("Message", attentionMessage) }
            if let error = session.errorMessage { row("Error", error) }
            if let pr = session.pullRequest {
                row("Pull request", pr.title ?? pr.url ?? "#\(pr.number.map(String.init) ?? "")")
            }
        }
    }

    /// `.frame(maxWidth: .infinity)` on the value (not a trailing `Spacer`) is what lets long
    /// values — a full session UUID, a deep project path — wrap onto a second line instead of
    /// being truncated, while still reliably stretching the row to the card's full width when
    /// the value is short. Identifiers (`monospaced`) read more legibly in a fixed-width face.
    private func row(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(monospaced ? .system(size: 11.5, design: .monospaced) : .system(size: 12))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Actions").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            WrapHStack {
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
    }

    private func actionButton(_ title: String, _ systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11.5))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    // MARK: - Recent activity

    private var activityLog: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent activity").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 7) {
                ForEach(session.recentActivity.reversed().prefix(20)) { entry in
                    HStack(alignment: .top, spacing: 10) {
                        Text(entry.timestamp.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                            .frame(width: 60, alignment: .leading)
                        Text(entry.message)
                            .font(.system(size: 11.5))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
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
