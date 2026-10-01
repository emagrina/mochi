import ServiceManagement

/// Wraps `SMAppService`, the modern, supported launch-at-login mechanism (macOS 13+) —
/// no custom launch daemon plists (product spec section 20).
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            // Best-effort: registration can fail outside a signed, installed .app bundle
            // (e.g. running straight out of .build during development). Not fatal.
        }
    }
}
