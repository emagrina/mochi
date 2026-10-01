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

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar-only: no Dock icon, no Cmd-Tab entry, no app menu.
        NSApplication.shared.setActivationPolicy(.accessory)
        model.start()
        if ProcessInfo.processInfo.environment["MOCHI_PREVIEW"] != nil {
            NSApplication.shared.activate(ignoringOtherApps: true)
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
        MenuBarExtra {
            PopoverView()
                .environment(appDelegate.model)
        } label: {
            MenuBarLabel(aggregate: appDelegate.model.aggregate, showCount: appDelegate.model.settings.showCountInMenuBar)
        }
        .menuBarExtraStyle(.window)

        // Lets the popover be rendered in a normal, screenshot-able window for visual
        // development/QA — a MenuBarExtra's own popover can only be opened by a real click on
        // the status item, which isn't scriptable. Completely inert for every real user: the
        // scene only actually opens when MOCHI_PREVIEW is set in the environment (nothing
        // sets it); SwiftUI's SceneBuilder can't structurally omit a Scene behind a runtime
        // `if`, so this is expressed as a launch-behavior toggle instead.
        Window("Mochi Preview", id: "preview") {
            PopoverView()
                .environment(appDelegate.model)
        }
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
