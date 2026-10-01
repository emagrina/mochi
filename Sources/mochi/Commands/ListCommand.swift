import ArgumentParser
import Foundation
import MochiCore

struct ListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List known agent sessions, replaying recorded events from disk."
    )

    @Flag(name: .long, help: "Include finished sessions.")
    var all: Bool = false

    @Flag(name: .long, help: "Print as JSON.")
    var json: Bool = false

    func run() async throws {
        let result = SessionProjection.replayAll()
        var sessions = Array(result.sessions.values)
        if !all {
            sessions = sessions.filter { $0.status != .done || $0.timeSinceLastActivity < 600 }
        }
        sessions.sort { lhs, rhs in
            if lhs.status.sortPriority != rhs.status.sortPriority {
                return lhs.status.sortPriority < rhs.status.sortPriority
            }
            return lhs.lastActivityAt > rhs.lastActivityAt
        }

        if json {
            CLISupport.printJSON(sessions)
            return
        }

        if sessions.isEmpty {
            print("No sessions. Run `mochi demo` to see Mochi in action, or `mochi start` to report a real one.")
            return
        }
        for session in sessions {
            print(SessionSummaryLine.render(session))
        }
        if result.malformedCount > 0 {
            print("(\(result.malformedCount) malformed event file(s) found — run `mochi doctor` for details)")
        }
    }
}
