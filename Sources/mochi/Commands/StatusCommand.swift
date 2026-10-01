import ArgumentParser
import Foundation
import MochiCore

struct StatusCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Report a status/activity update for a session."
    )

    @Option(name: .long, help: "Session id, as printed by `mochi start`.")
    var id: String

    @Option(name: .customLong("state"), help: "One of: \(CLISupport.knownStates.joined(separator: ", ")).")
    var state: String?

    @Option(name: .long, help: "Short free-form activity label, e.g. 'editing LibraryView.swift'.")
    var activity: String?

    @Option(name: .long, help: "Human-readable message shown in the activity log.")
    var message: String?

    @Option(name: .long, help: "Current task description, if it changed.")
    var task: String?

    func run() async throws {
        let validated = try CLISupport.validate(state: state)
        let event = MochiEvent(
            event: .status,
            agentId: id,
            task: task,
            status: validated,
            activity: activity,
            message: message,
            timestamp: Date()
        )
        do {
            try EventWriter().write(event)
        } catch {
            throw CLIError.writeFailed(String(describing: error))
        }
    }
}
