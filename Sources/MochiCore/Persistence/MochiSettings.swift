import Foundation

/// User-facing preferences (product spec section 19). Persisted as a small JSON file —
/// there's no case here for SQLite/SwiftData, it's a dozen scalars.
public struct MochiSettings: Codable, Sendable, Equatable {
    public enum Appearance: String, Codable, Sendable, CaseIterable {
        case system, light, dark
    }

    public var launchAtLogin: Bool
    public var showCountInMenuBar: Bool
    public var keepCompletedVisibleMinutes: Int
    public var notifyOnCompleted: Bool
    public var notifyOnAttention: Bool
    public var notifyOnError: Bool
    public var appearance: Appearance
    public var reducedMotion: Bool
    public var processedEventRetention: Int
    public var debugLoggingEnabled: Bool
    public var hasCompletedOnboarding: Bool
    public var openClawIntegrationEnabled: Bool
    public var processDetectionEnabled: Bool

    public static let `default` = MochiSettings(
        launchAtLogin: false,
        showCountInMenuBar: true,
        keepCompletedVisibleMinutes: 10,
        notifyOnCompleted: true,
        notifyOnAttention: true,
        notifyOnError: true,
        appearance: .system,
        reducedMotion: false,
        processedEventRetention: 500,
        debugLoggingEnabled: false,
        hasCompletedOnboarding: false,
        openClawIntegrationEnabled: true,
        processDetectionEnabled: true
    )

    public init(
        launchAtLogin: Bool,
        showCountInMenuBar: Bool,
        keepCompletedVisibleMinutes: Int,
        notifyOnCompleted: Bool,
        notifyOnAttention: Bool,
        notifyOnError: Bool,
        appearance: Appearance,
        reducedMotion: Bool,
        processedEventRetention: Int,
        debugLoggingEnabled: Bool,
        hasCompletedOnboarding: Bool,
        openClawIntegrationEnabled: Bool,
        processDetectionEnabled: Bool
    ) {
        self.launchAtLogin = launchAtLogin
        self.showCountInMenuBar = showCountInMenuBar
        self.keepCompletedVisibleMinutes = keepCompletedVisibleMinutes
        self.notifyOnCompleted = notifyOnCompleted
        self.notifyOnAttention = notifyOnAttention
        self.notifyOnError = notifyOnError
        self.appearance = appearance
        self.reducedMotion = reducedMotion
        self.processedEventRetention = processedEventRetention
        self.debugLoggingEnabled = debugLoggingEnabled
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.openClawIntegrationEnabled = openClawIntegrationEnabled
        self.processDetectionEnabled = processDetectionEnabled
    }

    // Custom decoding so a settings file written by an older or newer version of Mochi
    // (missing or carrying extra keys) loads with sensible defaults instead of failing.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = MochiSettings.default
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? fallback.launchAtLogin
        showCountInMenuBar = try container.decodeIfPresent(Bool.self, forKey: .showCountInMenuBar) ?? fallback.showCountInMenuBar
        keepCompletedVisibleMinutes = try container.decodeIfPresent(Int.self, forKey: .keepCompletedVisibleMinutes) ?? fallback.keepCompletedVisibleMinutes
        notifyOnCompleted = try container.decodeIfPresent(Bool.self, forKey: .notifyOnCompleted) ?? fallback.notifyOnCompleted
        notifyOnAttention = try container.decodeIfPresent(Bool.self, forKey: .notifyOnAttention) ?? fallback.notifyOnAttention
        notifyOnError = try container.decodeIfPresent(Bool.self, forKey: .notifyOnError) ?? fallback.notifyOnError
        appearance = try container.decodeIfPresent(Appearance.self, forKey: .appearance) ?? fallback.appearance
        reducedMotion = try container.decodeIfPresent(Bool.self, forKey: .reducedMotion) ?? fallback.reducedMotion
        processedEventRetention = try container.decodeIfPresent(Int.self, forKey: .processedEventRetention) ?? fallback.processedEventRetention
        debugLoggingEnabled = try container.decodeIfPresent(Bool.self, forKey: .debugLoggingEnabled) ?? fallback.debugLoggingEnabled
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? fallback.hasCompletedOnboarding
        openClawIntegrationEnabled = try container.decodeIfPresent(Bool.self, forKey: .openClawIntegrationEnabled) ?? fallback.openClawIntegrationEnabled
        processDetectionEnabled = try container.decodeIfPresent(Bool.self, forKey: .processDetectionEnabled) ?? fallback.processDetectionEnabled
    }
}
