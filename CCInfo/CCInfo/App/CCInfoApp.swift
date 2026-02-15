import SwiftUI
import AppKit

@main
struct CCInfoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appDelegate.appState)
        } label: {
            MenuBarLabel()
                .environmentObject(appDelegate.appState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appDelegate.appState)
        }

        Window(String(localized: "Sign in to Claude"), id: "auth") {
            AuthWebView()
                .environmentObject(appDelegate.appState)
        }
        .windowResizability(.contentSize)
    }
}

struct MenuBarLabel: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if appState.isAuthenticated, appState.usageData != nil {
            let slot1Value = appState.utilizationForSlot(appState.menuBarSlot1) ?? 0
            let slot2Value = appState.utilizationForSlot(appState.menuBarSlot2) ?? 0
            Image(nsImage: MenuBarImageRenderer.render(
                topRow: slot1Value,
                bottomRow: slot2Value,
                topSlot: appState.menuBarSlot1,
                bottomSlot: appState.menuBarSlot2
            ))
        } else {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
        }
    }
}

enum MenuBarImageRenderer {
    // MARK: - Layout Constants
    private enum Layout {
        static let width: CGFloat = 54
        static let height: CGFloat = 18
        static let barWidth: CGFloat = 28
        static let barHeight: CGFloat = 6
        static let rowHeight: CGFloat = 9
        static let barCornerRadius: CGFloat = 2
        static let textOffset: CGFloat = 2
        static let fontSize: CGFloat = 9
    }

    static func render(topRow: Double, bottomRow: Double, topSlot: MenuBarSlot = .fiveHour, bottomSlot: MenuBarSlot = .weeklyLimit) -> NSImage {
        let size = NSSize(width: Layout.width, height: Layout.height)

        let image = NSImage(size: size, flipped: false) { rect in
            drawRow(value: topRow, y: Layout.height - Layout.rowHeight, slot: topSlot)
            drawRow(value: bottomRow, y: 0, slot: bottomSlot)
            return true
        }

        image.isTemplate = false
        return image
    }

    private static func drawRow(value: Double, y: CGFloat, slot: MenuBarSlot) {
        let color = colorFor(value, slot: slot)
        let barY = y + 1.5

        // Background bar
        let bgRect = NSRect(x: 0, y: barY, width: Layout.barWidth, height: Layout.barHeight)
        let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: Layout.barCornerRadius, yRadius: Layout.barCornerRadius)
        NSColor.gray.withAlphaComponent(0.3).setFill()
        bgPath.fill()

        // Filled bar
        let fillWidth = Layout.barWidth * min(value, 100) / 100
        if fillWidth > 0 {
            let fillRect = NSRect(x: 0, y: barY, width: fillWidth, height: Layout.barHeight)
            let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: Layout.barCornerRadius, yRadius: Layout.barCornerRadius)
            color.setFill()
            fillPath.fill()
        }

        // Percentage text
        let text = "\(Int(value))%"
        let font = NSFont.monospacedDigitSystemFont(ofSize: Layout.fontSize, weight: .medium)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]
        let textSize = text.size(withAttributes: attributes)
        let textX = Layout.barWidth + Layout.textOffset
        let textY = y + (Layout.rowHeight - textSize.height) / 2
        text.draw(at: NSPoint(x: textX, y: textY), withAttributes: attributes)
    }

    private static func colorFor(_ value: Double, slot: MenuBarSlot) -> NSColor {
        switch value {
        case ..<50: return .systemGreen
        case ..<75: return .systemYellow
        case ..<90: return .systemOrange
        default: return .systemRed
        }
    }
}

