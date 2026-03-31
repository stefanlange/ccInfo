import SwiftUI
import AppKit

@main
struct ccInfoApp: App {
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
                .environmentObject(appDelegate.updateService)
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
    @State private var cachedImage: NSImage?
    @State private var cachedKey = MenuBarCacheKey()

    var body: some View {
        if appState.isAuthenticated, appState.usageData != nil {
            let slot1 = appState.menuBarSlot1
            let slot2 = appState.menuBarSlot2
            let slot1Value = Int(appState.utilizationForSlot(slot1) ?? 0)
            let slot2Value = Int(appState.utilizationForSlot(slot2) ?? 0)
            let key = MenuBarCacheKey(slot1: slot1, slot2: slot2, value1: slot1Value, value2: slot2Value)

            let image: NSImage = if key == cachedKey, let cached = cachedImage {
                cached
            } else {
                MenuBarImageRenderer.render(
                    topRow: Double(slot1Value),
                    bottomRow: Double(slot2Value),
                    topSlot: slot1,
                    bottomSlot: slot2
                )
            }

            Image(nsImage: image)
                .onChange(of: key) { _, newKey in
                    cachedImage = MenuBarImageRenderer.render(
                        topRow: Double(newKey.value1),
                        bottomRow: Double(newKey.value2),
                        topSlot: newKey.slot1,
                        bottomSlot: newKey.slot2
                    )
                    cachedKey = newKey
                }
                .onAppear {
                    cachedImage = image
                    cachedKey = key
                }
        } else {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
        }
    }
}

private struct MenuBarCacheKey: Equatable, Hashable {
    var slot1: MenuBarSlot = .fiveHour
    var slot2: MenuBarSlot = .weeklyLimit
    var value1: Int = -1
    var value2: Int = -1
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
        UtilizationThresholds.nsColor(for: value)
    }
}

