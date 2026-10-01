import SwiftUI
import MochiCore

/// The status item's label. Deliberately never animates (product spec section 11: "avoid
/// constant animation in the menu bar") and never relies on color alone — attention and
/// error states swap in an SF Symbol badge, not just a tint, so it reads correctly even in
/// grayscale/high-contrast menu bars.
struct MenuBarLabel: View {
    let aggregate: AggregateState
    let showCount: Bool

    var body: some View {
        HStack(spacing: 3) {
            symbol
            if showCount, let count = countText {
                Text(count)
            }
        }
    }

    @ViewBuilder
    private var symbol: some View {
        switch aggregate.headline {
        case .needsAttention:
            Image(systemName: "exclamationmark.triangle.fill")
        case .error:
            Image(systemName: "xmark.octagon.fill")
        default:
            Text("🍡")
        }
    }

    private var countText: String? {
        switch aggregate.headline {
        case .needsAttention(let count), .error(let count), .active(let count), .waiting(let count):
            return "\(count)"
        case .allDone, .empty:
            return nil
        }
    }
}
