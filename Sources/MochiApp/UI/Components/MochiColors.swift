import SwiftUI
import AppKit
import MochiCore

/// Semantic colors for the Mochi character and UI, each adapting to light/dark mode via
/// `NSColor`'s dynamic provider rather than hardcoded hex (product spec section 31).
/// There's no asset catalog here on purpose — this is a small, fixed palette, and keeping it
/// in code means it's reviewable in one file instead of scattered across color set JSON.
enum MochiColors {
    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }))
    }

    /// The mochi body itself: a soft, warm off-white that reads as "rice cake" rather than
    /// clinical white, with a slightly warmer dark-mode variant so it doesn't look washed out.
    static let body = dynamic(
        light: NSColor(calibratedWhite: 0.98, alpha: 1),
        dark: NSColor(calibratedWhite: 0.93, alpha: 1)
    )

    static let bodyShadow = dynamic(
        light: NSColor(calibratedWhite: 0.75, alpha: 0.5),
        dark: NSColor(calibratedWhite: 0.05, alpha: 0.6)
    )

    static let face = dynamic(
        light: NSColor(calibratedWhite: 0.15, alpha: 1),
        dark: NSColor(calibratedWhite: 0.15, alpha: 1)
    )

    /// A soft blush — the warmth on the character's "cheeks." Present on most expressions;
    /// deliberately left off the more subdued ones (error, offline, stale) where a flatter,
    /// less cheerful face reads more honestly (see `MochiAvatar`'s `showsBlush`).
    static let blush = dynamic(
        light: NSColor(calibratedRed: 0.95, green: 0.72, blue: 0.70, alpha: 0.55),
        dark: NSColor(calibratedRed: 0.95, green: 0.72, blue: 0.70, alpha: 0.30)
    )


    // MARK: - Surfaces

    /// The warm tint layered on top of `.regularMaterial` for the outer panel — this is what
    /// turns generic system translucency into design-reference.png's warm cream (light) /
    /// charcoal (dark) glass. `.regularMaterial` alone adapts to whatever's behind the window
    /// and reads neutral gray; this tint is what gives Mochi its own identity in both
    /// appearances regardless of desktop background.
    static let panelTint = dynamic(
        light: NSColor(calibratedRed: 0.99, green: 0.95, blue: 0.91, alpha: 0.62),
        dark: NSColor(calibratedRed: 0.13, green: 0.12, blue: 0.11, alpha: 0.55)
    )

    /// The card surface sitting on top of the panel — a touch more opaque and a touch
    /// warmer than the panel itself, so each card reads as its own soft pillowy object
    /// through contrast and shadow rather than a border (design-reference.png's card
    /// language: "material + subtle contrast + spacing + extremely subtle shadow").
    static let cardSurface = dynamic(
        light: NSColor(calibratedRed: 1.0, green: 0.98, blue: 0.95, alpha: 0.6),
        dark: NSColor(calibratedRed: 1.0, green: 0.98, blue: 0.96, alpha: 0.065)
    )

    static let cardShadow = dynamic(
        light: NSColor(calibratedRed: 0.55, green: 0.42, blue: 0.32, alpha: 0.16),
        dark: NSColor(calibratedWhite: 0.0, alpha: 0.35)
    )

    /// The subtler, round "chip" buttons (settings gear, row chevron) — visible but quiet
    /// until hovered.
    static let chipSurface = dynamic(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.55),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.10)
    )

    static let chipSurfaceHover = dynamic(
        light: NSColor(calibratedWhite: 1.0, alpha: 0.85),
        dark: NSColor(calibratedWhite: 1.0, alpha: 0.18)
    )

    // MARK: - Status pills

    /// Background/foreground pair for a status pill — restrained pastel background, a
    /// deeper (but still soft, never neon) foreground for the icon and label. Never the only
    /// signal for a status (the icon and text differ per state too — see `StatusPill`).
    struct PillColors {
        let background: Color
        let foreground: Color
    }

    static func pillColors(for status: AgentStatus) -> PillColors {
        switch status {
        case .working, .starting:
            return PillColors(
                background: dynamic(light: NSColor(calibratedRed: 0.90, green: 0.91, blue: 0.99, alpha: 1), dark: NSColor(calibratedRed: 0.20, green: 0.22, blue: 0.34, alpha: 1)),
                foreground: dynamic(light: NSColor(calibratedRed: 0.27, green: 0.32, blue: 0.75, alpha: 1), dark: NSColor(calibratedRed: 0.70, green: 0.74, blue: 0.98, alpha: 1))
            )
        case .testing:
            return PillColors(
                background: dynamic(light: NSColor(calibratedRed: 0.86, green: 0.95, blue: 0.94, alpha: 1), dark: NSColor(calibratedRed: 0.13, green: 0.28, blue: 0.27, alpha: 1)),
                foreground: dynamic(light: NSColor(calibratedRed: 0.13, green: 0.47, blue: 0.45, alpha: 1), dark: NSColor(calibratedRed: 0.56, green: 0.85, blue: 0.82, alpha: 1))
            )
        case .thinking:
            return PillColors(
                background: dynamic(light: NSColor(calibratedRed: 0.93, green: 0.89, blue: 0.98, alpha: 1), dark: NSColor(calibratedRed: 0.27, green: 0.20, blue: 0.35, alpha: 1)),
                foreground: dynamic(light: NSColor(calibratedRed: 0.52, green: 0.30, blue: 0.78, alpha: 1), dark: NSColor(calibratedRed: 0.80, green: 0.66, blue: 0.98, alpha: 1))
            )
        case .waiting:
            return PillColors(
                background: dynamic(light: NSColor(calibratedWhite: 0.93, alpha: 1), dark: NSColor(calibratedWhite: 0.26, alpha: 1)),
                foreground: dynamic(light: NSColor(calibratedWhite: 0.40, alpha: 1), dark: NSColor(calibratedWhite: 0.75, alpha: 1))
            )
        case .needsPermission:
            return PillColors(
                background: dynamic(light: NSColor(calibratedRed: 0.99, green: 0.92, blue: 0.80, alpha: 1), dark: NSColor(calibratedRed: 0.36, green: 0.27, blue: 0.11, alpha: 1)),
                foreground: dynamic(light: NSColor(calibratedRed: 0.62, green: 0.42, blue: 0.06, alpha: 1), dark: NSColor(calibratedRed: 0.98, green: 0.74, blue: 0.40, alpha: 1))
            )
        case .done:
            return PillColors(
                background: dynamic(light: NSColor(calibratedRed: 0.86, green: 0.95, blue: 0.87, alpha: 1), dark: NSColor(calibratedRed: 0.13, green: 0.28, blue: 0.16, alpha: 1)),
                foreground: dynamic(light: NSColor(calibratedRed: 0.16, green: 0.47, blue: 0.22, alpha: 1), dark: NSColor(calibratedRed: 0.55, green: 0.82, blue: 0.58, alpha: 1))
            )
        case .error:
            return PillColors(
                background: dynamic(light: NSColor(calibratedRed: 0.99, green: 0.88, blue: 0.87, alpha: 1), dark: NSColor(calibratedRed: 0.36, green: 0.16, blue: 0.15, alpha: 1)),
                foreground: dynamic(light: NSColor(calibratedRed: 0.68, green: 0.20, blue: 0.17, alpha: 1), dark: NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.52, alpha: 1))
            )
        case .stale:
            return PillColors(
                background: dynamic(light: NSColor(calibratedRed: 0.96, green: 0.93, blue: 0.87, alpha: 1), dark: NSColor(calibratedRed: 0.30, green: 0.27, blue: 0.20, alpha: 1)),
                foreground: dynamic(light: NSColor(calibratedRed: 0.52, green: 0.44, blue: 0.28, alpha: 1), dark: NSColor(calibratedRed: 0.80, green: 0.74, blue: 0.60, alpha: 1))
            )
        case .idle, .paused, .offline, .custom:
            return PillColors(
                background: dynamic(light: NSColor(calibratedWhite: 0.92, alpha: 1), dark: NSColor(calibratedWhite: 0.24, alpha: 1)),
                foreground: dynamic(light: NSColor(calibratedWhite: 0.45, alpha: 1), dark: NSColor(calibratedWhite: 0.70, alpha: 1))
            )
        }
    }

    // MARK: - Agent identity color

    /// A curated, soft palette for the little accent dot on each Mochi's shoulder. See
    /// `identityColor(for:)` for what it actually encodes.
    private static let identityPalette: [Color] = [
        dynamic(light: NSColor(calibratedRed: 0.27, green: 0.69, blue: 0.75, alpha: 1), dark: NSColor(calibratedRed: 0.40, green: 0.80, blue: 0.86, alpha: 1)), // cyan
        dynamic(light: NSColor(calibratedRed: 0.56, green: 0.42, blue: 0.86, alpha: 1), dark: NSColor(calibratedRed: 0.68, green: 0.56, blue: 0.95, alpha: 1)), // violet
        dynamic(light: NSColor(calibratedRed: 0.92, green: 0.56, blue: 0.20, alpha: 1), dark: NSColor(calibratedRed: 0.97, green: 0.66, blue: 0.34, alpha: 1)), // orange
        dynamic(light: NSColor(calibratedRed: 0.90, green: 0.40, blue: 0.52, alpha: 1), dark: NSColor(calibratedRed: 0.97, green: 0.54, blue: 0.64, alpha: 1)), // rose
        dynamic(light: NSColor(calibratedRed: 0.23, green: 0.58, blue: 0.42, alpha: 1), dark: NSColor(calibratedRed: 0.38, green: 0.74, blue: 0.56, alpha: 1)), // teal-green
        dynamic(light: NSColor(calibratedRed: 0.70, green: 0.58, blue: 0.14, alpha: 1), dark: NSColor(calibratedRed: 0.86, green: 0.72, blue: 0.30, alpha: 1)), // gold
        dynamic(light: NSColor(calibratedRed: 0.30, green: 0.47, blue: 0.86, alpha: 1), dark: NSColor(calibratedRed: 0.46, green: 0.62, blue: 0.97, alpha: 1)), // blue
        dynamic(light: NSColor(calibratedRed: 0.80, green: 0.42, blue: 0.70, alpha: 1), dark: NSColor(calibratedRed: 0.92, green: 0.56, blue: 0.82, alpha: 1))  // magenta
    ]

    /// Deterministic (stable across launches — never `Hashable`'s randomized `Hasher`) color
    /// for an agent identity key. This is the ONE thing the dot on a Mochi's shoulder means:
    /// which *agent* this is, not which provider or which status.
    ///
    /// Provider was considered and rejected: two different real agents are very often the
    /// same provider (two Claude sessions, two OpenClaw agents), so a provider-keyed dot
    /// would make unrelated agents look connected. Status was also rejected: it's already
    /// fully represented by the status pill a few points to the right, and reusing it on the
    /// dot would just repeat the same information in a second color instead of adding any.
    /// Agent identity is the one piece of information this exact spot can usefully add: two
    /// rows sharing a dot color are, confidently, two sessions of the *same* agent (see
    /// `AgentIdentity.key`) — reinforcing, in color, the same fact the shared title already
    /// tells you in text.
    static func identityColor(for key: String) -> Color {
        var hash: UInt64 = 5381
        for byte in key.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte) // djb2 — simple and stable, not Hasher
        }
        return identityPalette[Int(hash % UInt64(identityPalette.count))]
    }
}
