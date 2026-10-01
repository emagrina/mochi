import ArgumentParser
import Foundation
import MochiCore

struct DoneCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "done",
        abstract: "Tell Mochi this session finished successfully."
    )

    @Option(name: .long, help: "Session id.")
    var id: String

    @Option(name: .long, help: "Human-readable completion message.")
    var message: String?

    @Option(name: .long, help: "Pull request URL, if one was opened.")
    var prUrl: String?

    @Option(name: .long, help: "Pull request number, if known.")
    var prNumber: Int?

    @Option(name: .long, help: "Pull request title, if known.")
    var prTitle: String?

    func run() async throws {
        var pullRequest: PullRequestInfo?
        if prUrl != nil || prNumber != nil || prTitle != nil {
            pullRequest = PullRequestInfo(number: prNumber, url: prUrl, title: prTitle)
        }
        let event = MochiEvent(
            event: .completed,
            agentId: id,
            status: AgentStatus.done.rawValue,
            message: message,
            pullRequest: pullRequest,
            timestamp: Date()
        )
        do {
            try EventWriter().write(event)
        } catch {
            throw CLIError.writeFailed(String(describing: error))
        }
    }
}
