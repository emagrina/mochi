import AppKit
import SwiftUI
import MochiCore

/// Owns the single `AppModel` and starts its background work exactly once, from the one
/// guaranteed-single-fire hook AppKit gives us. A plain `@State` in the `App` struct's
/// `init()` isn't safe for this: SwiftUI can re-instantiate the `App` value across its
/// lifetime, and `init()` running twice would start the event-ingestion/polling loops twice.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only: no Dock icon, no Cmd-Tab entry, no app menu.
        NSApplication.shared.setActivationPolicy(.accessory)
        model.start()
        // Not a SwiftUI `MenuBarExtra` — see `StatusItemController` for why: that API wraps
        // its content in a system-managed container with its own small, fixed corner radius
        // and opaque background that no content-level modifier can remove, which is exactly
        // the "rectangular layer behind the rounded panel" this exists to avoid.
        let controller = StatusItemController(model: model)
        controller.start()
        statusItemController = controller
        if ProcessInfo.processInfo.environment["MOCHI_PREVIEW"] != nil {
            NSApplication.shared.activate(ignoringOtherApps: true)
            // Exercises the *actual* status item panel (not a stand-in) for visual QA,
            // since clicking the real status item isn't scriptable.
            controller.showPanel()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }
}

@main
struct MochiAppMain: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    private var previewRequested: Bool {
        ProcessInfo.processInfo.environment["MOCHI_PREVIEW"] != nil
    }

    var body: some Scene {
        // Lets the popover be rendered in a normal, screenshot-able window for visual
        // development/QA — a MenuBarExtra's own popover can only be opened by a real click on
        // the status item, which isn't scriptable. Completely inert for every real user: the
        // scene only actually opens when MOCHI_PREVIEW is set in the environment (nothing
        // sets it); SwiftUI's SceneBuilder can't structurally omit a Scene behind a runtime
        // `if`, so this is expressed as a launch-behavior toggle instead. Chrome (title bar,
        // traffic lights) is stripped via `PreviewChromeHider` so a screenshot of this window
        // can't be mistaken for the real popover's own chrome, which it never has.
        Window("Mochi Preview", id: "preview") {
            PopoverView()
                .environment(appDelegate.model)
                .background(PreviewChromeHider())
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(previewRequested ? .presented : .suppressed)

        Window("Welcome to Mochi", id: "onboarding") {
            OnboardingView()
                .environment(appDelegate.model)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)

        Settings {
            SettingsView()
                .environment(appDelegate.model)
        }
    }
}

/// Dev-preview-only: hides the traffic-light buttons `.windowStyle(.hiddenTitleBar)` alone
/// doesn't remove, so a screenshot of the preview window shows exactly what the real popover
/// shows — nothing else uses this, and it never runs unless MOCHI_PREVIEW opened this window.
private struct PreviewChromeHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { [weak view] in configure(view?.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in configure(nsView?.window) }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
    }
}
