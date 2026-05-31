import Foundation
import ServiceManagement

/// Autostart beim Anmelden (macOS 13+).
enum LoginItem {
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
            NSLog("LoginItem-Fehler: \(error.localizedDescription)")
        }
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
}
