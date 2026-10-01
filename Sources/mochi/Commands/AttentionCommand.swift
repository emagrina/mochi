import ArgumentParser
import Foundation
import MochiCore

struct AttentionCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "attention",
        abstract: "Tell Mochi this session needs the user — permission, input, or a decision."
    )

    @Option(name: .long, help: "Session id.")
    var id: String

    @Option(name: .long, help: "permission | input | decision | <anything custom>")
    var reason: String

    @Option(name: .long, help: "Human-readable explanation shown to the user.")
    var message: String

    func run() async throws {
        let event = MochiEvent(
            event: .attention,
            agentId: id,
            status: AgentStatus.needsPermission.rawValue,
            message: message,
            attentionReason: reason,
            timestamp: Date()
        )
        do {
            try EventWriter().write(event)
        } catch {
            throw CLIError.writeFailed(String(describing: error))
        }
    }
}
