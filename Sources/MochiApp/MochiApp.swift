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
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
    }
}

@main
struct MochiAppMain: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(appDelegate.model)
        } label: {
            MenuBarLabel(aggregate: appDelegate.model.aggregate, showCount: appDelegate.model.settings.showCountInMenuBar)
        }
        .menuBarExtraStyle(.window)

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
