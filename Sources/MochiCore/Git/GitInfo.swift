import Foundation

/// Reads local git metadata (current branch) for a project path, without ever touching the
/// network or requiring authentication (product spec section 27). Results are cached briefly
/// so a busy UI redrawing a popover doesn't shell out to `git` on every frame.
public actor GitInfo {
    public static let shared = GitInfo()

    private struct CacheEntry {
        let branch: String?
        let fetchedAt: Date
    }

    private var cache: [String: CacheEntry] = [:]
    private let ttl: TimeInterval = 30

    public init() {}

    public func branch(at path: String) async -> String? {
        if let cached = cache[path], Date().timeIntervalSince(cached.fetchedAt) < ttl {
            return cached.branch
        }
        let branch = Self.readBranch(at: path)
        cache[path] = CacheEntry(branch: branch, fetchedAt: Date())
        return branch
    }

    /// Runs `git rev-parse --abbrev-ref HEAD` with a fixed argument list and an explicit
    /// working directory — never a shell string built from untrusted input — so this can't
    /// become a command-injection vector even if `path` originated from an agent event.
    nonisolated private static func readBranch(at path: String) -> String? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", path, "rev-parse", "--abbrev-ref", "HEAD"]
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        guard let branch = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !branch.isEmpty else {
            return nil
        }
        return branch
    }
}
