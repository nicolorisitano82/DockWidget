import AppKit
import ServiceManagement

/// Opening at login is what makes "quitting frees the Dock" reversible: the
/// widgets the last quit removed come back on their own at the next start.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    @discardableResult
    static func set(_ enabled: Bool) -> Error? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            Diagnostics.write("apertura al login non riuscita: \(error.localizedDescription)")
            return error
        }
    }
}
