import SwiftUI
import MochiCore

/// The popover root: one large soft floating surface — design-reference.png's silhouette —
/// containing the header, the agent card list or empty state, and — only when there's
/// something worth saying — a problem summary. Built from native materials and semantic
/// colors throughout, specifically so it survives both system appearances without a
/// hardcoded background (see `MochiColors`).
struct PopoverView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @State private var hoveredSessionID: String?

    static let panelWidth: CGFloat = 500
    static let panelCornerRadius: CGFloat = 42

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            VStack(spacing: 0) {
                header
                if model.visibleSessions.isEmpty {
                    emptyHint
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
        // Width is fixed (design-reference.png's proportions); height is intentionally NOT —
        // it hugs however many cards are actually present and only caps out, scrolling
        // internally, once there are enough agents to need it. See `cardListHeight`.
        .frame(width: Self.panelWidth)
        .background {
            RoundedRectangle(cornerRadius: Self.panelCornerRadius, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: Self.panelCornerRadius, style: .continuous)
                        .fill(MochiColors.panelTint)
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.panelCornerRadius, style: .continuous))
        // No manual SwiftUI `.shadow()` here on purpose: the real popover's host window
        // (`StatusItemController`'s `BorderlessPanel`) and the dev preview window are both
        // non-opaque/clear, and AppKit computes a window's shadow from its actual rendered,
        // alpha-blended content in that case — so it already follows this rounded silhouette,
        // not a rectangular frame. A second, software shadow here would just double up.
        // `WindowTransparencyConfigurator` is the belt-and-suspenders version of that
        // isOpaque/backgroundColor setup for the dev preview window (a plain SwiftUI `Window`
        // scene, not something `StatusItemController` touches); the real popover's panel
        // already gets it directly where it's constructed.
        .background(WindowTransparencyConfigurator())
        .onAppear {
            if !model.settings.hasCompletedOnboarding {
                openWindow(id: "onboarding")
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            MochiMascotHeader(size: 92)
            VStack(alignment: .leading, spacing: 3) {
                Text("Mochi")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                Text(headerSubtitle)
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            settingsButton
        }
        .padding(EdgeInsets(top: 22, leading: 20, bottom: 14, trailing: 18))
    }

    private var settingsButton: some View {
        Button { openSettings() } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(MochiColors.chipSurface)
                )
        }
        .buttonStyle(.plain)
        .help("Settings")
        .accessibilityLabel("Settings")
    }

    /// Context-aware, one line, never cluttered: attention beats "working" beats a plain
    /// count, so the single most important fact is always what's shown.
    private var headerSubtitle: String {
        let aggregate = model.aggregate
        if aggregate.total == 0 { return "All quiet" }
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
            LazyVStack(spacing: AgentCard.cardSpacing) {
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
            .padding(.horizontal, 18)
            .padding(.bottom, 8)
        }
        .frame(height: cardListHeight)
    }

    /// Hugs the actual card count up to ~4.5 cards tall (design-reference.png shows exactly
    /// four comfortably), then holds there and lets the `ScrollView` take over — never
    /// shorter than one card, never so tall the window dwarfs a real menu bar utility just
    /// because a lot of agents happen to be active.
    private var cardListHeight: CGFloat {
        let cardHeight = AgentCard.cardHeight
        let gap = AgentCard.cardSpacing
        let count = max(1, model.visibleSessions.count)
        let needed = CGFloat(count) * cardHeight + CGFloat(count - 1) * gap
        let visibleCap = 4.5 * cardHeight + 3.5 * gap
        // The +18 (not just the scroll content's own small internal padding) is what keeps
        // the last card from crowding the panel's own big bottom corner radius when there's
        // no problem summary below it to provide that margin instead.
        return min(needed, visibleCap) + 18
    }

    /// The empty state keeps the header's own mascot as the only illustration (design spec:
    /// "do not create an unnecessary second illustration") and just adds one quiet line of
    /// guidance where the card list would otherwise be.
    private var emptyHint: some View {
        Text("They'll show up here when an agent reports in. Try `mochi demo` to see how it looks.")
            .font(.system(size: 12.5))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(EdgeInsets(top: 4, leading: 32, bottom: 30, trailing: 32))
    }

    // MARK: - Problem summary

    /// Only takes up space when there's something to say — design-reference.png shows no
    /// footer at all when every agent is fine, so neither does this. Uses the same soft,
    /// borderless surface language as the cards, just tinted by the pill colors.
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
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(colors.background))
            .padding(EdgeInsets(top: 10, leading: 18, bottom: 18, trailing: 18))
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

/// Reaches through to this view's own hosting `NSWindow` and forces it transparent/non-opaque
/// — the one piece of this design SwiftUI's `MenuBarExtra` doesn't hand you for free. Without
/// it, the window's default opaque background shows through as a plain rectangle at every
/// point our clipped, rounded content doesn't cover. Zero-size and otherwise invisible; safe
/// to drop into any view's `.background`.
private struct WindowTransparencyConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { [weak view] in configure(view?.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in configure(nsView?.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window, window.isOpaque else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
    }
}
