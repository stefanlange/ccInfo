import AppKit
import Foundation

enum SettingsWindowManager {
    static func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)

        // On macOS 14+, this reliably opens and focuses the Settings window
        // regardless of locale (Einstellungen, Settings, Paramètres, etc.)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }
}
