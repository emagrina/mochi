import ArgumentParser
import Foundation
import MochiCore

struct ErrorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "error",
        abstract: "Tell Mochi this session hit an error."
    )

    @Option(name: .long, help: "Session id.")
    var id: String

    @Option(name: .long, help: "Error message.")
    var message: String

    func run() async throws {
        let event = MochiEvent(
            event: .error,
            agentId: id,
            status: AgentStatus.error.rawValue,
            message: message,
            error: message,
            timestamp: Date()
        )
        do {
            try EventWriter().write(event)
        } catch {
            throw CLIError.writeFailed(String(describing: error))
        }
    }
}
