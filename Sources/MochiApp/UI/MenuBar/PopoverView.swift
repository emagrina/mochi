import SwiftUI
import MochiCore

/// The popover root: one large soft floating surface (`.regularMaterial`, clipped to a big
/// rounded rect — reference.png's silhouette) containing the header, the agent card list or
/// empty state, and — only when there's something worth saying — a problem summary. Built
/// from native materials and semantic colors throughout, specifically so it survives both
/// system appearances without a hardcoded background (see `MochiColors`).
struct PopoverView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @State private var hoveredSessionID: String?

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            VStack(spacing: 0) {
                header
                if model.visibleSessions.isEmpty {
                    EmptyStateView()
                } else {
                    cardList
                }
                problemSummary
            }
            .navigationDestination(for: String.self) { sessionID in
                if let session = model.session(id: sessionID) {
                    AgentDetailView(session: session, now: model.now)
                }
            }
        }
        // Width is fixed (reference.png's proportions); height is intentionally NOT — it
        // hugs however many cards are actually present (product spec: "do not make the
        // window unnecessarily tall") and only caps out, scrolling internally, once there
        // are enough agents to need it. See `cardListHeight`.
        .frame(width: 400)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(MochiColors.cardBorder, lineWidth: 1)
        )
        .onAppear {
            if !model.settings.hasCompletedOnboarding {
                openWindow(id: "onboarding")
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            MochiMascotHeader(size: 76)
            VStack(alignment: .leading, spacing: 2) {
                Text("Mochi")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(headerSubtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            settingsButton
        }
        .padding(EdgeInsets(top: 20, leading: 20, bottom: 16, trailing: 16))
    }

    private var settingsButton: some View {
        Button { openSettings() } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(Circle().fill(MochiColors.chipSurface))
        }
        .buttonStyle(.plain)
        .help("Settings")
        .accessibilityLabel("Settings")
    }

    /// Context-aware, one line, never cluttered: attention beats "working" beats a plain
    /// count, so the single most important fact is always what's shown (product spec's
    /// "whichever wording best represents the actual current state").
    private var headerSubtitle: String {
        let aggregate = model.aggregate
        if aggregate.total == 0 { return "No agents working" }
        if aggregate.needsAttention > 0 {
            return aggregate.needsAttention == 1 ? "1 needs you" : "\(aggregate.needsAttention) need you"
        }
        if aggregate.activeCount > 0 {
            return aggregate.activeCount == 1 ? "1 working" : "\(aggregate.activeCount) working"
        }
        return aggregate.total == 1 ? "1 agent" : "\(aggregate.total) agents"
    }

    // MARK: - Cards

    private var cardList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(model.visibleSessions) { session in
                    NavigationLink(value: session.id) {
                        AgentCard(
                            session: session,
                            now: model.now,
                            reducedMotion: model.settings.reducedMotion,
                            isHovered: hoveredSessionID == session.id
                        )
                        .onHover { hovering in hoveredSessionID = hovering ? session.id : nil }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
        }
        .frame(height: cardListHeight)
    }

    /// Hugs the actual card count up to ~5 cards tall, then holds there and lets the
    /// `ScrollView` take over — never shorter than one card, never so tall the window
    /// dwarfs a real menu bar utility just because a lot of agents happen to be active.
    private var cardListHeight: CGFloat {
        let cardHeight: CGFloat = 94
        let gap: CGFloat = 10
        let count = max(1, model.visibleSessions.count)
        let needed = CGFloat(count) * cardHeight + CGFloat(count - 1) * gap
        let visibleCap = 4.6 * cardHeight + 3.6 * gap
        return min(needed, visibleCap) + 4
    }

    // MARK: - Problem summary

    /// Only takes up space when there's something to say — reference.png shows no footer at
    /// all when every agent is fine, so neither does this.
    @ViewBuilder
    private var problemSummary: some View {
        let aggregate = model.aggregate
        if aggregate.needsAttention > 0 || aggregate.errors > 0 {
            let colors = MochiColors.pillColors(for: aggregate.needsAttention > 0 ? .needsPermission : .error)
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text(problemText(aggregate))
                    .font(.system(size: 12.5, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(colors.foreground)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(colors.background))
            .padding(EdgeInsets(top: 10, leading: 16, bottom: 16, trailing: 16))
        }
    }

    private func problemText(_ aggregate: AggregateState) -> String {
        var parts: [String] = []
        if aggregate.needsAttention > 0 {
            parts.append(aggregate.needsAttention == 1 ? "1 agent needs you" : "\(aggregate.needsAttention) agents need you")
        }
        if aggregate.errors > 0 {
            parts.append(aggregate.errors == 1 ? "1 hit a problem" : "\(aggregate.errors) hit problems")
        }
        return parts.joined(separator: " · ")
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            MochiAvatar(status: .idle, size: 64)
            Text("No agents working")
                .font(.system(size: 14, weight: .semibold))
            Text("They'll show up here when an agent reports in.\nTry `mochi demo` to see how it looks.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }
}
