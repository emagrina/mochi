import Foundation

/// Runs an external command with a hard timeout and captured output. Used by adapters that
/// shell out to a locally installed CLI (e.g. `openclaw`) — never to execute anything an
/// agent event told us to run (see `TerminalLauncher` for that security note too).
public enum ProcessRunner {
    public struct Result: Sendable {
        public let exitCode: Int32
        public let stdout: Data
        public let stderr: Data
        public let timedOut: Bool
    }

    /// Manually synchronized completion flag shared between the termination handler and the
    /// timeout watchdog. Marked `@unchecked Sendable` because every access is guarded by
    /// `lock` — Swift's data-race checker can't see that, so we assert it ourselves here.
    private final class CompletionGate: @unchecked Sendable {
        private let lock = NSLock()
        private var finished = false
        var timedOut = false

        /// Returns true the first time it's called (i.e. caller should act); false on any
        /// subsequent call, so the termination handler and the watchdog can never both act.
        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !finished else { return false }
            finished = true
            return true
        }
    }

    /// `executable` is looked up via `/usr/bin/env` so callers can pass a bare command name
    /// (e.g. "openclaw") and rely on the inherited PATH, same as a shell would, without us
    /// ever constructing an actual shell string.
    public static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 5) async -> Result {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executable] + arguments

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            let gate = CompletionGate()

            process.terminationHandler = { proc in
                guard gate.claim() else { return }
                let out = outPipe.fileHandleForReading.readDataToEndOfFile()
                let err = errPipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: Result(exitCode: proc.terminationStatus, stdout: out, stderr: err, timedOut: gate.timedOut))
            }

            do {
                try process.run()
            } catch {
                guard gate.claim() else { return }
                continuation.resume(returning: Result(exitCode: -1, stdout: Data(), stderr: Data(), timedOut: false))
                return
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                guard process.isRunning else { return }
                gate.timedOut = true
                process.terminate()
            }
        }
    }
}
