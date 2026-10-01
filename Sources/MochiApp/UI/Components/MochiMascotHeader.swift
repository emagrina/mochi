import AppKit
import SwiftUI

/// The larger, decorated Mochi in the popover header — the app's own "face," not any one
/// agent's. Unlike the small per-agent `MochiAvatar`, this is the actual provided artwork
/// (design-reference.png's header mascot), not a SwiftUI-drawn approximation: the brief was
/// explicit that this exact character, dango and all, should appear here untouched. The image
/// ships pre-cropped to its opaque content (see `Scripts/generate-assets.swift`'s sibling
/// processing step) so there's no dead transparent margin to account for when sizing it.
public struct MochiMascotHeader: View {
    public let size: CGFloat

    public init(size: CGFloat = 92) {
        self.size = size
    }

    public var body: some View {
        Image(nsImage: Self.image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(height: size)
            .accessibilityHidden(true) // decorative — the header's own text carries the meaning.
    }

    private static let image: NSImage = {
        guard let url = Bundle.module.url(forResource: "MochiHeaderMascot", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            assertionFailure("MochiHeaderMascot.png missing from the app bundle")
            return NSImage()
        }
        return image
    }()
}
