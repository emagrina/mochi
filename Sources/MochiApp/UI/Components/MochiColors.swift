import SwiftUI
import AppKit

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

    static let claudeAccent = dynamic(
        light: NSColor(calibratedRed: 0.80, green: 0.42, blue: 0.27, alpha: 1),
        dark: NSColor(calibratedRed: 0.88, green: 0.52, blue: 0.36, alpha: 1)
    )

    static let codexAccent = dynamic(
        light: NSColor(calibratedRed: 0.23, green: 0.52, blue: 0.52, alpha: 1),
        dark: NSColor(calibratedRed: 0.35, green: 0.68, blue: 0.68, alpha: 1)
    )

    static let openClawAccent = dynamic(
        light: NSColor(calibratedRed: 0.42, green: 0.36, blue: 0.70, alpha: 1),
        dark: NSColor(calibratedRed: 0.58, green: 0.52, blue: 0.84, alpha: 1)
    )

    static let attention = dynamic(
        light: NSColor(calibratedRed: 0.86, green: 0.55, blue: 0.11, alpha: 1),
        dark: NSColor(calibratedRed: 0.95, green: 0.65, blue: 0.25, alpha: 1)
    )

    static let errorTint = dynamic(
        light: NSColor(calibratedRed: 0.80, green: 0.25, blue: 0.22, alpha: 1),
        dark: NSColor(calibratedRed: 0.92, green: 0.40, blue: 0.37, alpha: 1)
    )

    static let successTint = dynamic(
        light: NSColor(calibratedRed: 0.26, green: 0.56, blue: 0.32, alpha: 1),
        dark: NSColor(calibratedRed: 0.42, green: 0.72, blue: 0.48, alpha: 1)
    )
}
