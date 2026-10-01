import Foundation

/// A shared ISO 8601 date format *with fractional seconds*, used everywhere Mochi encodes a
/// `Date` to JSON or to a filename.
///
/// This matters more than it looks: `EventWriter` names inbox files by timestamp so a
/// cold-started app can replay them in order, and several CLI commands run back-to-back
/// (`mochi start` immediately followed by `mochi status`) land within the same wall-clock
/// *second*. Foundation's plain `.iso8601` JSONEncoder strategy truncates to whole seconds,
/// which made same-second events sort by their random UUID suffix instead of call order —
/// a real bug caught while smoke-testing the CLI. Millisecond precision fixes it.
public enum MochiDateCoding {
    // `ISO8601DateFormatter` isn't marked `Sendable`, but used purely for stateless
    // `string(from:)`/`date(from:)` calls it's safe to share across threads in practice;
    // `nonisolated(unsafe)` documents that this is a deliberate, reviewed exception.
    nonisolated(unsafe) public static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Falls back to whole-second parsing for any timestamp written by an older tool/version
    /// that doesn't include fractional seconds.
    nonisolated(unsafe) private static let fallbackFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    public static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    public static func date(from string: String) -> Date? {
        formatter.date(from: string) ?? fallbackFormatter.date(from: string)
    }

    /// A filesystem-safe, lexicographically-sortable rendering (`:` isn't valid-but-annoying
    /// in filenames, so it's swapped for `-`).
    public static func filenameSafeString(from date: Date) -> String {
        string(from: date).replacingOccurrences(of: ":", with: "-")
    }

    public static let jsonEncodingStrategy: JSONEncoder.DateEncodingStrategy = .custom { date, encoder in
        var container = encoder.singleValueContainer()
        try container.encode(string(from: date))
    }

    public static let jsonDecodingStrategy: JSONDecoder.DateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let date = date(from: string) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(string)")
        }
        return date
    }
}
