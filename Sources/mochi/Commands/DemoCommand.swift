import ArgumentParser
import Foundation
import MochiCore

/// `mochi demo` — runs a handful of fake agents through realistic state transitions so
/// Mochi.app's UI can be exercised without any real coding agent running (product spec
/// section 35). Deliberately touches every status the UI needs to render at least once:
/// starting, thinking, working, testing, needsPermission, done, and error. The last two
/// scenarios also share an `agentKey`/`agentName` ("Chief of Staff") on purpose, to exercise
/// "multiple sessions, one agent identity" without needing a live OpenClaw install.
struct DemoCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "demo",
        abstract: "Simulate a few agents working, for UI development and demos."
    )

    @Option(name: .long, help: "How many scripted agents to run (cycles through 6 scenarios).")
    var agents: Int = 6

    @Option(name: .long, help: "Seconds between each simulated step.")
    var stepDelay: Double = 2.5

    @Flag(name: .long, help: "Remove all demo data (identified by source, never by name) instead of running the demo. Never touches real sessions.")
    var cleanup: Bool = false

    func run() async throws {
        if cleanup {
            let result = DemoCleanup.removeAllDemoData()
            if result.removedSessionCount == 0 {
                print("No demo sessions found.")
            } else {
                print("Removed \(result.removedSessionCount) demo session(s) (\(result.removedFileCount) event file(s)).")
            }
            return
        }

        let writer = EventWriter()
        print("Mochi demo: simulating \(agents) agent(s). Open Mochi.app (or run `mochi list`) to watch.")
        print("Demo sessions auto-expire a couple of minutes after their last event — run `mochi demo --cleanup` to remove them immediately.")

        let scenarios = Self.scenarios(count: agents)
        await withTaskGroup(of: Void.self) { group in
            for scenario in scenarios {
                group.addTask {
                    await Self.run(scenario, writer: writer, stepDelay: stepDelay)
                }
            }
        }
        print("Demo finished.")
    }

    private struct Scenario {
        let agentId: String
        let provider: String
        let project: String
        let projectPath: String
        let task: String
        let branch: String?
        let steps: [Step]
        /// Shared across multiple scenarios to demonstrate "same agent, different sessions" —
        /// see the two "demo-openclaw-chief-of-staff" scenarios below.
        var agentKey: String? = nil
        var agentName: String? = nil
    }

    private enum Step {
        case status(AgentStatus, activity: String?, message: String?)
        case attention(reason: String, message: String)
        case done(message: String, prNumber: Int?, prURL: String?, prTitle: String?)
        case error(message: String)
    }

    private static func scenarios(count: Int) -> [Scenario] {
        let templates: [Scenario] = [
            Scenario(
                agentId: "demo-claude-huginn",
                provider: "claude",
                project: "Huginn",
                projectPath: NSHomeDirectory() + "/Documents/Projects/huginn",
                task: "Redesign Library page",
                branch: "feature/library-redesign",
                steps: [
                    .status(.thinking, activity: "Planning the new layout", message: "Reading LibraryView.swift"),
                    .status(.working, activity: "Editing LibraryView.swift", message: "Redesigning Library"),
                    .status(.testing, activity: "Running UI tests", message: "Running frontend tests"),
                    .status(.working, activity: "Polishing spacing", message: "Tests passed, polishing"),
                    .done(message: "Library redesign complete.", prNumber: 42, prURL: "https://github.com/example/huginn/pull/42", prTitle: "Redesign Library page")
                ]
            ),
            Scenario(
                agentId: "demo-codex-huginn-api",
                provider: "codex",
                project: "Huginn API",
                projectPath: NSHomeDirectory() + "/Documents/Projects/huginn-api",
                task: "Fix auth token refresh bug",
                branch: "fix/token-refresh",
                steps: [
                    .status(.working, activity: "Reading auth middleware", message: "Investigating token refresh bug"),
                    .status(.testing, activity: "Running integration tests", message: "Running tests"),
                    .error(message: "3 tests failed: token refresh race condition still reproduces")
                ]
            ),
            Scenario(
                agentId: "demo-claude-serafin",
                provider: "claude",
                project: "Serafín",
                projectPath: NSHomeDirectory() + "/Documents/Projects/serafin",
                task: "Update onboarding docs",
                branch: nil,
                steps: [
                    .status(.working, activity: "Drafting docs", message: "Writing onboarding guide"),
                    .attention(reason: "permission", message: "Needs permission to run `rm -rf dist/` before rebuilding docs"),
                    .status(.working, activity: "Rebuilding docs", message: "Permission granted, continuing"),
                    .done(message: "Onboarding guide updated.", prNumber: nil, prURL: nil, prTitle: nil)
                ]
            ),
            Scenario(
                agentId: "demo-codex-portfolio",
                provider: "codex",
                project: "Portfolio",
                projectPath: NSHomeDirectory() + "/Documents/Projects/portfolio",
                task: "Refactor image pipeline",
                branch: "refactor/image-pipeline",
                steps: [
                    .status(.thinking, activity: "Reading image pipeline code", message: nil),
                    .status(.working, activity: "Refactoring resize logic", message: "Refactoring image pipeline")
                ]
            ),
            // These two share an agentKey/agentName on purpose: this is the exact shape an
            // OpenClaw-style persistent agent takes in real usage (see OpenClawAdapter) — one
            // named identity, multiple concurrent sessions, one of which may finish while
            // another keeps going. Demonstrates that the UI shows "Chief of Staff" as the
            // title for both rows (not "OpenClaw" twice) while keeping them distinguishable.
            Scenario(
                agentId: "demo-openclaw-chief-of-staff-main",
                provider: "openclaw",
                project: "Aenari",
                projectPath: NSHomeDirectory() + "/Documents/Projects/aenari",
                task: "Coordinating the team",
                branch: nil,
                steps: [
                    .status(.working, activity: nil, message: "Coordinating implementation"),
                    .done(message: "Session finished.", prNumber: nil, prURL: nil, prTitle: nil)
                ],
                agentKey: "demo-openclaw:chief-of-staff",
                agentName: "Chief of Staff"
            ),
            Scenario(
                agentId: "demo-openclaw-chief-of-staff-dashboard",
                provider: "openclaw",
                project: "Dashboard session",
                projectPath: NSHomeDirectory() + "/Documents/Projects/aenari",
                task: "Aenari",
                branch: nil,
                steps: [
                    .status(.thinking, activity: nil, message: "Reviewing subagent output"),
                    .status(.working, activity: nil, message: "Coordinating implementation")
                ],
                agentKey: "demo-openclaw:chief-of-staff",
                agentName: "Chief of Staff"
            )
        ]
        guard count != templates.count else { return templates }
        guard count > 0 else { return [] }
        return (0..<count).map { index in
            let template = templates[index % templates.count]
            guard index >= templates.count else { return template }
            let suffix = index / templates.count + 1
            return Scenario(
                agentId: "\(template.agentId)-\(suffix)",
                provider: template.provider,
                project: "\(template.project) \(suffix)",
                projectPath: template.projectPath,
                task: template.task,
                branch: template.branch,
                steps: template.steps,
                // Keep sharing the same agentKey across repeats so the "two sessions, one
                // agent" demo still works even at --agents counts above the template count.
                agentKey: template.agentKey,
                agentName: template.agentName
            )
        }
    }

    private static func run(_ scenario: Scenario, writer: EventWriter, stepDelay: Double) async {
        let startEvent = MochiEvent(
            event: .start,
            agentId: scenario.agentId,
            provider: scenario.provider,
            agentKey: scenario.agentKey,
            agentDisplayName: scenario.agentName,
            // Unconditional — see SessionSource.demo's doc comment. There is no flag or
            // scenario option that can make a `mochi demo` session claim to be anything else.
            source: SessionSource.demo.rawValue,
            project: scenario.project,
            projectPath: scenario.projectPath,
            task: scenario.task,
            status: AgentStatus.starting.rawValue,
            branch: scenario.branch,
            timestamp: Date()
        )
        _ = try? writer.write(startEvent)
        try? await Task.sleep(nanoseconds: UInt64(stepDelay * 1_000_000_000))

        for step in scenario.steps {
            let event: MochiEvent
            switch step {
            case .status(let status, let activity, let message):
                event = MochiEvent(event: .status, agentId: scenario.agentId, status: status.rawValue, activity: activity, message: message, timestamp: Date())
            case .attention(let reason, let message):
                event = MochiEvent(event: .attention, agentId: scenario.agentId, status: AgentStatus.needsPermission.rawValue, message: message, attentionReason: reason, timestamp: Date())
            case .done(let message, let prNumber, let prURL, let prTitle):
                let pr = (prNumber != nil || prURL != nil || prTitle != nil) ? PullRequestInfo(number: prNumber, url: prURL, title: prTitle) : nil
                event = MochiEvent(event: .completed, agentId: scenario.agentId, status: AgentStatus.done.rawValue, message: message, pullRequest: pr, timestamp: Date())
            case .error(let message):
                event = MochiEvent(event: .error, agentId: scenario.agentId, status: AgentStatus.error.rawValue, message: message, error: message, timestamp: Date())
            }
            _ = try? writer.write(event)
            try? await Task.sleep(nanoseconds: UInt64(stepDelay * 1_000_000_000))
        }
    }
}
