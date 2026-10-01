import AppKit
import Foundation
import MochiCore

/// Every "open X" action available from the agent detail view, each only exposed when the
/// underlying data actually supports it (product spec section 13: "do not create fake
/// buttons") and each going through validated, known-shape operations rather than anything
/// derived unsanitized from an event payload (section 23).
@MainActor
enum AgentActions {
    static func canOpenProject(_ session: AgentSession) -> Bool {
        guard let path = session.projectPath else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    static func openProjectInFinder(_ session: AgentSession) {
        guard let path = session.projectPath, FileManager.default.fileExists(atPath: path) else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }

    static func canOpenTerminal(_ session: AgentSession) -> Bool {
        guard let path = session.projectPath else { return false }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    static func openTerminal(_ session: AgentSession) {
        guard let path = session.projectPath else { return }
        try? PreferredTerminal.current().open(directoryPath: path)
    }

    static func canOpenPullRequest(_ session: AgentSession) -> Bool {
        guard let urlString = session.pullRequest?.url, let url = URL(string: urlString) else { return false }
        return url.scheme == "https" || url.scheme == "http"
    }

    static func openPullRequest(_ session: AgentSession) {
        guard let urlString = session.pullRequest?.url, let url = URL(string: urlString),
              url.scheme == "https" || url.scheme == "http" else { return }
        NSWorkspace.shared.open(url)
    }

    static func copySessionID(_ session: AgentSession) {
        copy(session.id)
    }

    static func copyProjectPath(_ session: AgentSession) {
        guard let path = session.projectPath else { return }
        copy(path)
    }

    private static func copy(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}
