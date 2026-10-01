import Foundation

/// Opens a project directory in a terminal app. Abstracted behind a protocol so adding a
/// second terminal (iTerm2, Terminal.app as a deliberate choice rather than just a fallback)
/// never touches call sites (product spec section 28).
///
/// Security note: every implementation takes a `directoryPath` that MUST be validated by the
/// caller (see `AgentDetailActions`) to be an existing, real directory before it reaches here.
/// We only ever launch via `/usr/bin/open` with an argument array (never a shell string), so
/// even an adversarial path value can't be used for command injection — at worst it fails to
/// open because the path doesn't exist.
public protocol TerminalLauncher: Sendable {
    var isAvailable: Bool { get }
    var displayName: String { get }
    func open(directoryPath: String) throws
}

public enum TerminalLauncherError: Error {
    case notADirectory
    case appNotFound
}

/// Ghostty is only scriptable on macOS via `open -na Ghostty.app --args --working-directory=<path>`.
/// Ghostty explicitly documents that launching it directly from argv0 on macOS is unsupported
/// ("On macOS, launching the terminal emulator from the CLI is not supported... Use
/// `open -na Ghostty.app`"), and `working-directory` is a real, documented Ghostty config key
/// (confirmed locally via `ghostty +show-config --default`). There is no Ghostty URL scheme
/// and no way to target an *existing* window/session — this opens a new window.
public struct GhosttyLauncher: TerminalLauncher {
    public let appURL: URL

    public init(appURL: URL = URL(fileURLWithPath: "/Applications/Ghostty.app")) {
        self.appURL = appURL
    }

    public var isAvailable: Bool { FileManager.default.fileExists(atPath: appURL.path) }
    public var displayName: String { "Ghostty" }

    public func open(directoryPath: String) throws {
        try Self.validate(directoryPath)
        guard isAvailable else { throw TerminalLauncherError.appNotFound }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-na", appURL.path, "--args", "--working-directory=\(directoryPath)"]
        try process.run()
    }

    static func validate(_ path: String) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw TerminalLauncherError.notADirectory
        }
    }
}

/// Fallback used when Ghostty isn't installed. `open -a Terminal <path>` is standard,
/// documented Launch Services behavior: when given a directory, Terminal.app opens a new
/// window `cd`'d into it.
public struct TerminalAppLauncher: TerminalLauncher {
    public init() {}

    public var isAvailable: Bool {
        FileManager.default.fileExists(atPath: "/System/Applications/Utilities/Terminal.app")
            || FileManager.default.fileExists(atPath: "/Applications/Utilities/Terminal.app")
    }
    public var displayName: String { "Terminal" }

    public func open(directoryPath: String) throws {
        try GhosttyLauncher.validate(directoryPath)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", directoryPath]
        try process.run()
    }
}

public enum PreferredTerminal {
    /// Ghostty first (this user's daily driver, per product spec), Terminal.app otherwise.
    public static func current() -> TerminalLauncher {
        let ghostty = GhosttyLauncher()
        if ghostty.isAvailable { return ghostty }
        return TerminalAppLauncher()
    }
}
