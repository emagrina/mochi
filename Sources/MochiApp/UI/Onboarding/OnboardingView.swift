import AppKit
import SwiftUI
import MochiCore

/// First-launch explainer (product spec section 18). One page, four short beats — this is
/// not a multi-screen wizard, just enough context that the empty state makes sense.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var cliFound = Self.locateCLI() != nil

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                MochiAvatar(status: .working, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to Mochi").font(.title3).bold()
                    Text("A tiny menu bar companion for your coding agents.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }

            beat(number: 1, text: "Mochi lives in your menu bar — click the 🍡 any time to see what's running.")
            beat(number: 2, text: "Agents (or scripts) report what they're doing by calling the `mochi` CLI, or by using an integration like OpenClaw.")
            beat(number: 3, text: cliFound
                ? "The `mochi` CLI is on your PATH — you're ready to go."
                : "The `mochi` CLI isn't on your PATH yet. Build it with `swift build` and add `.build/out/Products/Debug` to your PATH, or copy the binary to /usr/local/bin yourself — Mochi won't modify your shell configuration for you.")
            beat(number: 4, text: "Notifications tell you when something finishes, fails, or needs your attention — never for routine chatter.")

            HStack {
                Button("Copy `mochi demo` command") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString("mochi demo", forType: .string)
                }
                Spacer()
                Button("Get started") {
                    model.settings.hasCompletedOnboarding = true
                    dismissWindow(id: "onboarding")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func beat(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold))
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.secondary.opacity(0.15)))
            Text(text).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
        }
    }

    static func locateCLI() -> String? {
        let candidates = ["/usr/local/bin/mochi", "/opt/homebrew/bin/mochi"]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }
}
