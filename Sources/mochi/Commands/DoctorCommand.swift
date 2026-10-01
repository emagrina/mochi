import ArgumentParser
import Foundation
import MochiCore

struct DoctorCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Diagnose Mochi's local setup: permissions, stale sessions, integrations."
    )

    @Flag(name: .long, help: "Print as JSON.")
    var json: Bool = false

    struct Check: Encodable {
        let name: String
        let ok: Bool
        let detail: String
    }

    func run() async throws {
        var checks: [Check] = []
        let paths = MochiPaths.shared

        let dirsOK = paths.ensureDirectoriesExist()
        checks.append(Check(name: "Event directory", ok: dirsOK, detail: dirsOK ? paths.root.path : "Could not create \(paths.root.path)"))

        let writable = FileManager.default.isWritableFile(atPath: paths.inbox.path)
        checks.append(Check(name: "Inbox writable", ok: writable, detail: paths.inbox.path))

        let quarantineCount = (try? FileManager.default.contentsOfDirectory(atPath: paths.quarantine.path).count) ?? 0
        checks.append(Check(
            name: "Malformed events",
            ok: quarantineCount == 0,
            detail: quarantineCount == 0 ? "none quarantined" : "\(quarantineCount) file(s) in \(paths.quarantine.path)"
        ))

        let stateExists = FileManager.default.fileExists(atPath: paths.sessionsStateFile.path)
        var appSeemsRunning = false
        if stateExists, let attrs = try? FileManager.default.attributesOfItem(atPath: paths.sessionsStateFile.path),
           let modified = attrs[.modificationDate] as? Date {
            appSeemsRunning = Date().timeIntervalSince(modified) < 120
        }
        checks.append(Check(
            name: "Mochi.app",
            ok: stateExists,
            detail: stateExists
                ? (appSeemsRunning ? "state file updated recently — app looks active" : "state file exists but hasn't updated in a while — app may not be running")
                : "no state snapshot yet — app has never run, or hasn't ingested an event yet"
        ))

        // SessionProjection.replayAll already reconciles lifecycle (stale/offline transitions,
        // demo expiry) the same way the live app does, so what's reported here is the
        // truthful, current state — not just whatever a stale persisted "working" said.
        let projection = SessionProjection.replayAll(paths: paths)
        checks.append(Check(name: "Recorded events", ok: true, detail: "\(projection.sessions.count) session(s) known; \(projection.malformedCount) malformed"))

        var bySource: [SessionSource: Int] = [:]
        var staleCount = 0, offlineCount = 0
        for session in projection.sessions.values {
            bySource[session.source, default: 0] += 1
            if session.status == .stale { staleCount += 1 }
            if session.status == .offline { offlineCount += 1 }
        }
        let sourceBreakdown = bySource
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.rawValue)=\($0.value)" }
            .joined(separator: ", ")
        checks.append(Check(name: "Sessions by source", ok: true, detail: sourceBreakdown.isEmpty ? "none" : sourceBreakdown))

        checks.append(Check(
            name: "Stale sessions",
            ok: staleCount == 0,
            detail: staleCount == 0 ? "none" : "\(staleCount) session(s) quiet for over \(Int(StaleDetector.staleThreshold / 60)) minutes — no longer confirmed active"
        ))
        checks.append(Check(
            name: "Offline sessions",
            ok: true,
            detail: offlineCount == 0 ? "none" : "\(offlineCount) session(s) presumed stopped after \(Int(StaleDetector.offlineThreshold / 60)) minutes of silence"
        ))

        let openClawStatus = await OpenClawAdapter().currentStatus()
        checks.append(Check(name: "OpenClaw CLI", ok: openClawStatus == .connected, detail: describe(openClawStatus)))

        if json {
            CLISupport.printJSON(checks)
        } else {
            for check in checks {
                let mark = check.ok ? "✓" : "✗"
                print("\(mark) \(check.name): \(check.detail)")
            }
        }
    }

    private func describe(_ status: IntegrationStatus) -> String {
        switch status {
        case .connected: return "found on PATH"
        case .notConfigured: return "not found on PATH"
        case .unavailable(let reason): return reason
        }
    }
}
