import AppKit
import SwiftUI
import Observation
import MochiCore

/// Owns the real status item and its popover panel directly in AppKit, instead of going
/// through SwiftUI's `MenuBarExtra`.
///
/// `MenuBarExtra(.window)` wraps whatever content you give it in a system-managed container
/// that applies its own default material background and a small, fixed corner radius — that
/// wrapping happens *outside* the content view SwiftUI hands you, so no modifier on our own
/// root view (background, clipShape, or even reaching through to `NSWindow.isOpaque`) can
/// remove it. The visible result is exactly what it looks like: a big rounded card sitting
/// inside a smaller-radius rounded system panel, with a sliver of that system panel's own
/// background showing at each corner. There's no supported way to opt out of it while still
/// using `MenuBarExtra` for presentation, so this controller replaces it wholesale: a plain
/// `NSStatusItem` for the glyph, and a borderless, non-opaque, `.clear`-background `NSPanel`
/// that we position and size ourselves, hosting the exact same `PopoverView` SwiftUI content.
/// With nothing but our own clipped, rounded SwiftUI view between the desktop and the panel's
/// transparent backing, the corners are genuinely transparent — not a second, differently
/// shaped layer of chrome.
@MainActor
final class StatusItemController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var statusItem: NSStatusItem!
    private var panel: BorderlessPanel!
    private var hostingView: NSHostingView<AnyView>!

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        statusItem = item

        let hosting = NSHostingView(rootView: AnyView(PopoverView().environment(model)))
        hostingView = hosting

        let newPanel = BorderlessPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // The whole point: a fully transparent, chrome-less host. `PopoverView`'s own
        // `.background`/`.clipShape` is the ONLY thing that paints anything — everything
        // outside its rounded silhouette stays genuinely see-through, and the floating
        // shadow AppKit draws for a non-opaque borderless window follows that same rendered
        // shape rather than the panel's rectangular frame.
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = true
        newPanel.level = .statusBar
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        newPanel.isReleasedWhenClosed = false
        newPanel.hidesOnDeactivate = false
        newPanel.contentView = hosting
        newPanel.delegate = self
        panel = newPanel

        updateStatusItemAppearance()
        observeModel()
    }

    @objc private func togglePanel() {
        if panel.isVisible {
            closePanel()
        } else {
            showPanel()
        }
    }

    /// Internal rather than private: `MOCHI_PREVIEW` calls this directly (see `MochiApp.swift`)
    /// to exercise this exact panel without a real click, since a click on the status item
    /// isn't scriptable for visual QA.
    func showPanel() {
        syncPanelSize()
        panel.setFrameOrigin(panelOrigin())
        panel.makeKeyAndOrderFront(nil)
    }

    /// Anchored under the status item button — but, like Docker Desktop's menu bar panel
    /// rather than a centered popover, opening with its LEFT edge near the icon so the panel
    /// extends mostly to the icon's right. Falls back to the screen's top-right instead of
    /// silently doing nothing if the button's window can't be resolved (which does happen
    /// transiently, and is this sandbox's permanent reality since its menu bar isn't
    /// rendering any status items at all right now — see the repo's notes on that environment
    /// limitation).
    private func panelOrigin() -> CGPoint {
        guard let button = statusItem.button, let buttonWindow = button.window else {
            let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
            return CGPoint(x: screen.maxX - panel.frame.width - 12, y: screen.maxY - panel.frame.height - 6)
        }
        let buttonFrameInScreen = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        // The screen that actually contains the status item — never assume `.main` (the
        // screen with the active window), which on a multi-monitor setup is frequently a
        // different display than the one the menu bar icon lives on.
        let visible = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        return Self.clampedPanelOrigin(iconFrame: buttonFrameInScreen, panelSize: panel.frame.size, visibleScreenFrame: visible)
    }

    /// The actual positioning math, pulled out as a pure function of its geometry so it's
    /// exercisable without a real, clickable `NSStatusItem` (this sandbox doesn't have one —
    /// see `panelOrigin()`'s doc comment) and so every input combination — icon near the left
    /// edge, the right edge, a narrow display, a huge one — is just a `CGRect` to construct,
    /// not a real screen to find.
    ///
    /// Like Docker Desktop's menu bar panel rather than a centered popover: prefers opening
    /// with its LEFT edge at the icon's own left edge (so it reads as anchored to the icon,
    /// extending rightward), clamped to the screen that actually contains the icon.
    static func clampedPanelOrigin(
        iconFrame: CGRect,
        panelSize: CGSize,
        visibleScreenFrame: CGRect,
        margin: CGFloat = 8,
        leadingOffset: CGFloat = 10,
        gapBelowIcon: CGFloat = 6
    ) -> CGPoint {
        let y = iconFrame.minY - panelSize.height - gapBelowIcon
        let preferredX = iconFrame.minX - leadingOffset
        // Pull left first if the preferred position would run the right edge off screen...
        var x = min(preferredX, visibleScreenFrame.maxX - panelSize.width - margin)
        // ...then push right if THAT pulled the left edge off screen too (a narrow display,
        // or an icon already near the screen's left edge) — the right-edge clamp always wins
        // when both can't be satisfied, since staying on screen matters more than how far
        // right the panel leans.
        x = max(x, visibleScreenFrame.minX + margin)
        return CGPoint(x: x, y: y)
    }

    private func closePanel() {
        panel.orderOut(nil)
    }

    /// `PopoverView` sizes its own width and hugs its own height to the current card count
    /// (see `PopoverView.cardListHeight`); this just asks the hosting view for that ideal
    /// size and resizes the panel to match, anchored at its top edge so it grows/shrinks
    /// downward from the status item rather than from wherever its old bottom edge was.
    private func syncPanelSize() {
        let size = hostingView.fittingSize
        guard size.width > 0, size.height > 0 else { return }
        var frame = panel.frame
        let topY = frame.origin.y + frame.height
        frame.size = size
        frame.origin.y = topY - size.height
        panel.setFrame(frame, display: panel.isVisible)
    }

    private func observeModel() {
        withObservationTracking {
            _ = model.aggregate
            _ = model.settings.showCountInMenuBar
            // Detail and the main list are different heights; this is what makes the panel
            // resize when `PopoverView` navigates between them, not just when the agent list
            // itself changes.
            _ = model.selectedSessionID
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.updateStatusItemAppearance()
                if self.panel.isVisible { self.syncPanelSize() }
                self.observeModel()
            }
        }
    }

    /// Ports `MenuBarLabel`'s old SwiftUI logic to plain `NSStatusBarButton` properties — same
    /// rule (never color alone; attention/error swap the glyph itself, not just a tint) and
    /// the same bundled template image, just assigned directly instead of composed in a View.
    private func updateStatusItemAppearance() {
        guard let button = statusItem.button else { return }
        let aggregate = model.aggregate
        switch aggregate.headline {
        case .needsAttention:
            button.image = Self.symbolImage("exclamationmark.triangle.fill")
        case .error:
            button.image = Self.symbolImage("xmark.octagon.fill")
        default:
            button.image = Self.glyph
        }
        if model.settings.showCountInMenuBar, let count = Self.countText(aggregate) {
            button.title = " \(count)"
            button.imagePosition = .imageLeading
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
        }
    }

    private static func countText(_ aggregate: AggregateState) -> String? {
        switch aggregate.headline {
        case .needsAttention(let count), .error(let count), .active(let count), .waiting(let count):
            return "\(count)"
        case .allDone, .empty:
            return nil
        }
    }

    private static func symbolImage(_ name: String) -> NSImage {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
        image.isTemplate = true
        return image
    }

    /// The neutral Mochi glyph, loaded once. `isTemplate = true` is what makes this a proper
    /// macOS template image: AppKit renders it using only the alpha channel, automatically
    /// picking black/white/selection-tint to match the current menu bar appearance.
    private static let glyph: NSImage = {
        guard let url = Bundle.module.url(forResource: "MochiMenuBarTemplate", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            assertionFailure("MochiMenuBarTemplate.png missing from the app bundle — run Scripts/generate-assets.swift")
            return NSImage()
        }
        image.isTemplate = true
        let aspect = image.size.width / max(image.size.height, 1)
        let pointHeight: CGFloat = 18
        image.size = NSSize(width: (pointHeight * aspect).rounded(), height: pointHeight)
        return image
    }()

    func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === panel else { return }
        closePanel()
    }
}

/// A borderless panel that can still become key — needed for its SwiftUI content's buttons,
/// navigation links, and hover state to actually respond to clicks. `.nonactivatingPanel`
/// (set where this is constructed) is what keeps those clicks from also activating Mochi
/// itself, which has no Dock icon or app menu to activate into in the first place.
private final class BorderlessPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
