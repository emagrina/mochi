import AppKit
import SwiftUI
import MochiCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView {
            GeneralSettingsView(settings: $model.settings)
                .tabItem { Label("General", systemImage: "gearshape") }
            NotificationSettingsView(settings: $model.settings)
                .tabItem { Label("Notifications", systemImage: "bell") }
            AppearanceSettingsView(settings: $model.settings)
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
            IntegrationsSettingsView(settings: $model.settings)
                .tabItem { Label("Integrations", systemImage: "puzzlepiece.extension") }
            AdvancedSettingsView(model: model)
                .tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 440, height: 320)
    }
}

private struct GeneralSettingsView: View {
    @Binding var settings: MochiSettings
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Toggle("Launch Mochi at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in LaunchAtLogin.setEnabled(newValue) }
            Toggle("Show active count in menu bar", isOn: $settings.showCountInMenuBar)
            Stepper(
                "Keep finished agents visible for \(settings.keepCompletedVisibleMinutes) min",
                value: $settings.keepCompletedVisibleMinutes,
                in: 1...60
            )
        }
        .padding(20)
    }
}

private struct NotificationSettingsView: View {
    @Binding var settings: MochiSettings

    var body: some View {
        Form {
            Toggle("Notify when a task completes", isOn: $settings.notifyOnCompleted)
            Toggle("Notify when an agent needs you", isOn: $settings.notifyOnAttention)
            Toggle("Notify on errors", isOn: $settings.notifyOnError)
            Text("Mochi never notifies for routine status updates (thinking, testing, working) — only for the three above, and only once per condition.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }
}

private struct AppearanceSettingsView: View {
    @Binding var settings: MochiSettings

    var body: some View {
        Form {
            Picker("Appearance", selection: $settings.appearance) {
                Text("System").tag(MochiSettings.Appearance.system)
                Text("Light").tag(MochiSettings.Appearance.light)
                Text("Dark").tag(MochiSettings.Appearance.dark)
            }
            .pickerStyle(.radioGroup)
            Toggle("Reduce motion", isOn: $settings.reducedMotion)
            Text("Mochi also respects the system-wide Reduce Motion setting automatically.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }
}

private struct IntegrationsSettingsView: View {
    @Binding var settings: MochiSettings
    @State private var openClawStatus: IntegrationStatus = .notConfigured
    @State private var checked = false

    var body: some View {
        Form {
            Section {
                Toggle("OpenClaw", isOn: $settings.openClawIntegrationEnabled)
                statusLine(openClawStatus, reliability: .heuristic)
                Text("Polls `openclaw sessions list` and `openclaw approvals pending` locally. Activity detail is limited to what OpenClaw itself reports — see docs/integrations.md.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Process detection", isOn: $settings.processDetectionEnabled)
                Text("Notices when a claude, codex, or openclaw process is running. Shows as \"Detected\" with no activity detail — it's a nudge toward real instrumentation, not a replacement for it.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Section {
                Text("Claude Code — add a hook that calls the `mochi` CLI. Codex — no supported hook API found; use the CLI from a wrapper script.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .task {
            guard !checked else { return }
            checked = true
            openClawStatus = await OpenClawAdapter().currentStatus()
        }
    }

    private func statusLine(_ status: IntegrationStatus, reliability: IntegrationReliability) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(status == .connected ? Color.green : Color.secondary)
                .frame(width: 6, height: 6)
            Text(label(for: status))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
    }

    private func label(for status: IntegrationStatus) -> String {
        switch status {
        case .connected: return "openclaw CLI found — heuristic status, real approval detection"
        case .notConfigured: return "openclaw CLI not found on PATH"
        case .unavailable(let reason): return reason
        }
    }
}

private struct AdvancedSettingsView: View {
    let model: AppModel
    @State private var showingResetConfirmation = false

    var body: some View {
        Form {
            Button("Open Mochi Data Directory") {
                NSWorkspace.shared.open(MochiPaths.shared.root)
            }
            Button("Reset Local History…", role: .destructive) {
                showingResetConfirmation = true
            }
            .confirmationDialog(
                "Reset Mochi's local history?",
                isPresented: $showingResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("Reset History", role: .destructive) {
                    model.resetLocalHistory()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This clears all known sessions and recorded events. Settings are kept. This cannot be undone.")
            }
            Stepper(
                "Keep last \(model.settings.processedEventRetention) processed events",
                value: Binding(
                    get: { model.settings.processedEventRetention },
                    set: { model.settings.processedEventRetention = $0 }
                ),
                in: 100...2000,
                step: 100
            )
            Toggle("Debug logging", isOn: Binding(
                get: { model.settings.debugLoggingEnabled },
                set: { model.settings.debugLoggingEnabled = $0 }
            ))
            if model.quarantineCount > 0 {
                Text("\(model.quarantineCount) malformed event(s) quarantined this session. Run `mochi doctor` for details.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }
}
