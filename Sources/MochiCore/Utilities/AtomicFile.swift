import Foundation

/// Atomic file writes, the backbone of Mochi's concurrency safety.
///
/// Every writer (CLI invocations from multiple agents, adapters, the app's own state
/// snapshot) writes to a uniquely-named temp file in the *same directory* as the final
/// destination, then `rename(2)`s it into place. Rename within one filesystem/volume is
/// atomic on APFS/HFS+, so readers never observe a partially-written file, and two writers
/// can never corrupt each other's output — each gets its own temp file and its own rename.
public enum AtomicFile {
    /// Writes `data` to `url` atomically. If `url`'s directory doesn't exist, it is created.
    public static func write(_ data: Data, to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tempURL = dir.appendingPathComponent(".tmp-\(UUID().uuidString)")
        try data.write(to: tempURL, options: .atomic)
        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
        } catch {
            // `url` doesn't exist yet (first write ever): rename is still atomic, just not a replace.
            try? FileManager.default.removeItem(at: url)
            try FileManager.default.moveItem(at: tempURL, to: url)
        }
    }

    /// Writes a brand-new file under `directory` with a unique name, returning its URL.
    /// Used for inbox events where every write is a new file, never an overwrite.
    public static func writeUnique(_ data: Data, directory: URL, prefix: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = "\(prefix)-\(UUID().uuidString).json"
        let finalURL = directory.appendingPathComponent(name)
        let tempURL = directory.appendingPathComponent(".tmp-\(UUID().uuidString)")
        try data.write(to: tempURL, options: .atomic)
        try FileManager.default.moveItem(at: tempURL, to: finalURL)
        return finalURL
    }
}
