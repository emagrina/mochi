import ArgumentParser
import Foundation
import MochiCore

struct InspectCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inspect",
        abstract: "Show everything Mochi knows about one session."
    )

    @Argument(help: "Session id.")
    var id: String

    @Flag(name: .long, help: "Print as JSON.")
    var json: Bool = false

    func run() async throws {
        let result = SessionProjection.replayAll()
        guard let session = result.sessions[id] else {
            throw CLIError.sessionNotFound(id)
        }

        if json {
            CLISupport.printJSON(session)
            return
        }

        print("Agent        \(session.displayName)")
        if let descriptor = session.agentIdentity.secondaryDescriptor { print("             \(descriptor)") }
        print("Provider     \(session.provider.displayName)")
        print("Agent key    \(session.agentIdentity.key)")
        print("Session id   \(session.id)")
        print("Status       \(session.status.friendlyLabel) (\(session.status.rawValue))")
        if let project = session.projectName { print("Project      \(project)") }
        if let path = session.projectPath { print("Path         \(path)") }
        if let branch = session.branch { print("Branch       \(branch)") }
        if let task = session.currentTask { print("Task         \(task)") }
        if let activity = session.currentActivity { print("Activity     \(activity)") }
        print("Started      \(session.startedAt)")
        print("Last active  \(session.lastActivityAt)")
        if let finished = session.finishedAt { print("Finished     \(finished)") }
        print("Elapsed      \(SessionSummaryLine.formatDuration(session.elapsed))")
        if let reason = session.attentionReason { print("Attention    \(reason.friendlyLabel)") }
        if let attentionMessage = session.attentionMessage { print("             \(attentionMessage)") }
        if let error = session.errorMessage { print("Error        \(error)") }
        if let pr = session.pullRequest { print("Pull request #\(pr.number.map(String.init) ?? "?") \(pr.url ?? "")") }
        if !session.recentActivity.isEmpty {
            print("\nRecent activity:")
            for entry in session.recentActivity.suffix(15) {
                print("  \(entry.timestamp)  \(entry.message)")
            }
        }
    }
}
