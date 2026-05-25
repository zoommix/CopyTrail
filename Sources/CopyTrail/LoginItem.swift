import ServiceManagement

/// Wrapper around SMAppService for our "launch at login" toggle.
/// macOS 13+ API; macOS keeps the state itself, so no extra persistence
/// is needed on our side.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Try to register / unregister, then return the resulting state.
    /// If the bundle isn't in a registerable location (running directly
    /// from .build/, etc.) or the user denies the system prompt, the
    /// returned value may differ from the requested one.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // The system also surfaces failures through SMAppService.status,
            // so callers should re-check isEnabled rather than trust the
            // requested value.
        }
        return isEnabled
    }
}
