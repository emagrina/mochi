import SwiftUI
import MochiCore

/// A small rounded pill pairing an icon with the friendly status label — never color alone
/// (the icon and text both change per state too, so the pill still reads correctly in
/// grayscale/high-contrast). Replaces the earlier flat `StatusBadge`; kept as its own file
/// since both `AgentCard` and `AgentDetailView` use it.
struct StatusPill: View {
    let status: AgentStatus

    var body: some View {
        let colors = MochiColors.pillColors(for: status)
        HStack(spacing: 5) {
            Image(systemName: symbolName)
                .font(.system(size: 11, weight: .bold))
            Text(status.friendlyLabel)
                .font(.system(size: 12.5, weight: .bold))
        }
        .foregroundStyle(colors.foreground)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(colors.background))
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
        case .stale: return "wifi.slash"
        case .offline: return "power"
        case .custom: return "questionmark.circle.fill"
        }
    }
}
