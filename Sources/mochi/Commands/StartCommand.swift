import ArgumentParser
import Foundation
import MochiCore

struct StartCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "start",
        abstract: "Tell Mochi a new agent session has started."
    )

    @Option(name: .long, help: "Provider/tool name, e.g. claude, codex, or anything custom.")
    var agent: String

    @Option(name: .long, help: "Project display name.")
    var project: String?

    @Option(name: .customLong("path"), help: "Absolute path to the project directory.")
    var projectPath: String?

    @Option(name: .long, help: "What the agent is about to do.")
    var task: String?

    @Option(name: .long, help: "Explicit session id. Auto-generated and printed if omitted.")
    var id: String?

    @Option(name: .long, help: "The agent's own name/identity, e.g. 'Frontend Agent' or 'Atlas' — shown as the primary title instead of the provider name. Omit it and this session is its own standalone agent.")
    var agentName: String?

    @Option(name: .long, help: "Stable key shared across multiple sessions of the same agent (so Mochi knows two --id values are the same agent). Defaults to this session's own id, i.e. not shared, if omitted.")
    var agentKey: String?

    @Option(name: .long, help: "A role/persona descriptor, if distinct from --agent-name.")
    var agentRole: String?

    @Option(name: .long, help: "Git branch, if known.")
    var branch: String?

    @Flag(name: .long, help: "Print the result as JSON (includes the generated id).")
    var json: Bool = false

    func run() async throws {
        let agentId = id ?? CLISupport.generateAgentId(provider: agent, project: project)
        let event = MochiEvent(
            event: .start,
            agentId: agentId,
            provider: agent,
            agentKey: agentKey,
            agentDisplayName: agentName,
            agentRole: agentRole,
            project: project,
            projectPath: projectPath,
            task: task,
            status: AgentStatus.starting.rawValue,
            branch: branch,
            timestamp: Date()
        )
        do {
            try EventWriter().write(event)
        } catch {
            throw CLIError.writeFailed(String(describing: error))
        }

        if json {
            CLISupport.printJSON(["id": agentId])
        } else {
            print(agentId)
        }
    }
}
