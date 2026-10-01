import AppKit
import SwiftUI
import MochiCore

/// The larger, decorated Mochi in the popover header — the app's own "face," not any one
/// agent's. Deliberately reuses `MochiAvatar` wholesale (a calm, content `.idle` expression,
/// no identity dot — this isn't standing in for a specific agent) rather than duplicating its
/// drawing code, and adds one small flourish on top: a dango-style skewer, the one place in
/// the UI that's purely decorative branding rather than conveying state. Its expression stays
/// constant regardless of aggregate state on purpose — the menu bar glyph already signals
/// "something needs you" via its own icon swap; the header doesn't need to repeat that, and a
/// mascot that changed mood with every status mix would be exactly the kind of busyness the
/// product spec's "Mochi should feel calm" asks to avoid.
public struct MochiMascotHeader: View {
    public let size: CGFloat

    public init(size: CGFloat = 92) {
        self.size = size
    }

    public var body: some View {
        ZStack {
            MochiAvatar(status: .idle, identityKey: nil, size: size)
            skewer
        }
    }

    private var skewer: some View {
        ZStack {
            Capsule()
                .fill(MochiMascotHeader.stickColor)
                .frame(width: max(1.5, size * 0.022), height: size * 0.4)
            VStack(spacing: size * 0.03) {
                ball(MochiMascotHeader.pink, size: size)
                ball(MochiMascotHeader.cream, size: size)
                ball(MochiMascotHeader.matcha, size: size)
            }
            .offset(y: -size * 0.1)
        }
        .rotationEffect(.degrees(-16))
        .offset(x: -size * 0.1, y: -size * 0.44)
    }

    /// A thin dark edge on every ball, not just a fill — without it the pale cream bead
    /// visually disappears against whatever's directly behind it (the mochi's own equally
    /// pale body, or a light popover background), regardless of app appearance.
    private func ball(_ color: Color, size: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: size * 0.1, height: size * 0.1)
            .overlay(Circle().strokeBorder(.black.opacity(0.14), lineWidth: 0.75))
            .shadow(color: .black.opacity(0.22), radius: size * 0.012, y: size * 0.006)
    }

    private static let stickColor = MochiColors.dynamic(
        light: NSColor(calibratedRed: 0.62, green: 0.47, blue: 0.30, alpha: 1),
        dark: NSColor(calibratedRed: 0.62, green: 0.47, blue: 0.30, alpha: 1)
    )
    private static let pink = MochiColors.dynamic(
        light: NSColor(calibratedRed: 0.93, green: 0.58, blue: 0.62, alpha: 1),
        dark: NSColor(calibratedRed: 0.93, green: 0.58, blue: 0.62, alpha: 1)
    )
    private static let cream = MochiColors.dynamic(
        light: NSColor(calibratedRed: 0.96, green: 0.90, blue: 0.80, alpha: 1),
        dark: NSColor(calibratedRed: 0.96, green: 0.90, blue: 0.80, alpha: 1)
    )
    private static let matcha = MochiColors.dynamic(
        light: NSColor(calibratedRed: 0.56, green: 0.68, blue: 0.40, alpha: 1),
        dark: NSColor(calibratedRed: 0.56, green: 0.68, blue: 0.40, alpha: 1)
    )
}
