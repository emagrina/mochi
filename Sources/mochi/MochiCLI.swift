import ArgumentParser

@main
struct MochiCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mochi",
        abstract: "Tell Mochi what your agent is doing.",
        discussion: """
        Mochi is a menu bar companion for autonomous coding agents. This CLI writes small
        event files into ~/.mochi/inbox that Mochi.app (or any script) can read — see
        docs/protocol.md for the wire format.
        """,
        version: "1.0.0",
        subcommands: [
            StartCommand.self,
            StatusCommand.self,
            AttentionCommand.self,
            DoneCommand.self,
            ErrorCommand.self,
            ListCommand.self,
            InspectCommand.self,
            DoctorCommand.self,
            DemoCommand.self
        ]
    )
}
