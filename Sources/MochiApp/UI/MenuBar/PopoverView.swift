import SwiftUI
import MochiCore

struct PopoverView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            VStack(spacing: 0) {
                header
                Divider()
                if model.visibleSessions.isEmpty {
                    EmptyStateView()
                        .frame(maxHeight: .infinity)
                } else {
                    List(model.visibleSessions) { session in
                        NavigationLink(value: session.id) {
                            AgentRow(session: session, now: model.now, reducedMotion: model.settings.reducedMotion)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
                Divider()
                footer
            }
            .navigationDestination(for: String.self) { sessionID in
                if let session = model.session(id: sessionID) {
                    AgentDetailView(session: session, now: model.now)
                }
            }
        }
        .frame(width: 360, height: 440)
        .onAppear {
            if !model.settings.hasCompletedOnboarding {
                openWindow(id: "onboarding")
            }
        }
    }

    private var header: some View {
        HStack {
            Text("🍡 Mochi").font(.system(size: 14, weight: .bold))
            Spacer()
            Button {
                openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .padding(EdgeInsets(top: 10, leading: 14, bottom: 8, trailing: 10))
    }

    private var footer: some View {
        HStack {
            Text(model.aggregate.summaryLine)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            Spacer()
            if model.quarantineCount > 0 {
                Label("\(model.quarantineCount)", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .help("Malformed events were ignored. See Settings > Advanced.")
            }
        }
        .padding(EdgeInsets(top: 8, leading: 14, bottom: 10, trailing: 14))
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 10) {
            MochiAvatar(status: .idle, provider: .generic(""), size: 56)
            Text("No Mochis working right now.")
                .font(.system(size: 13, weight: .medium))
            Text("They'll show up here when an agent reports in.\nTry `mochi demo` to see how it looks.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }
}
