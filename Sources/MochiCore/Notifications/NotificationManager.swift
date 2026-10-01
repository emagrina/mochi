import Foundation
import UserNotifications

/// Thin wrapper around `UNUserNotificationCenter`. Deliberately narrow: three notification
/// *kinds* only (completed / attention / error), each gated by its own settings toggle, and
/// no notification is ever sent for routine status chatter (thinking/testing/working) — the
/// product spec is explicit that spam here would defeat the point of the app.
///
/// Local notifications require the process to be running from a real `.app` bundle with a
/// bundle identifier; see `Scripts/build-app.sh`. Running the raw executable via `swift run`
/// will cause authorization requests to silently no-op, which is expected and documented in
/// the README rather than worked around.
public struct NotificationManager: Sendable {
    public init() {}

    public func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    public func notifyCompleted(agentName: String, project: String?, message: String?) async {
        let projectPart = project.map { " \($0)" } ?? ""
        await post(
            title: "Mochi",
            body: "\(agentName) finished\(projectPart). \(message ?? "Task complete.")",
            category: "completed"
        )
    }

    public func notifyAttention(agentName: String, project: String?, reason: String) async {
        let projectPart = project.map { " in \($0)" } ?? ""
        await post(
            title: "Mochi",
            body: "\(agentName) needs you\(projectPart). \(reason)",
            category: "attention"
        )
    }

    public func notifyError(agentName: String, project: String?, message: String) async {
        let projectPart = project.map { " in \($0)" } ?? ""
        await post(
            title: "Mochi",
            body: "\(agentName) hit a problem\(projectPart). \(message)",
            category: "error"
        )
    }

    private func post(title: String, body: String, category: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}
