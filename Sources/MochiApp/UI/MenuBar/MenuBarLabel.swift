import AppKit
import SwiftUI
import MochiCore

/// The status item's label. Deliberately never animates (product spec section 11: "avoid
/// constant animation in the menu bar") and never relies on color alone — attention and
/// error states swap in an SF Symbol badge, not just a tint, so it reads correctly even in
/// grayscale/high-contrast menu bars.
struct MenuBarLabel: View {
    let aggregate: AggregateState
    let showCount: Bool

    /// The neutral Mochi glyph, loaded once. `isTemplate = true` is what makes this a proper
    /// macOS template image: AppKit renders it using only the alpha channel, automatically
    /// picking black/white/selection-tint to match the current menu bar appearance — the
    /// asset itself is never hardcoded to a color (see Scripts/generate-assets.swift, which
    /// normalizes the source artwork to black-on-transparent specifically so there's nothing
    /// color-dependent for that rule to apply to).
    private static let glyph: NSImage = {
        guard let url = Bundle.module.url(forResource: "MochiMenuBarTemplate", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            assertionFailure("MochiMenuBarTemplate.png missing from the app bundle — run Scripts/generate-assets.swift")
            return NSImage()
        }
        image.isTemplate = true
        // The exported PNG is intentionally much higher resolution than this (see the
        // generator script) so Retina rendering stays crisp; setting `.size` explicitly to a
        // point size (not a pixel size) is what tells AppKit to draw it at menu-bar optical
        // scale — matching neighboring system status items like Wi-Fi or Control Center —
        // rather than at its native pixel dimensions.
        let aspect = image.size.width / max(image.size.height, 1)
        let pointHeight: CGFloat = 18
        image.size = NSSize(width: (pointHeight * aspect).rounded(), height: pointHeight)
        return image
    }()

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
            Image(nsImage: Self.glyph)
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
