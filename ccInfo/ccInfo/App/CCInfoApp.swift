import SwiftUI
import AppKit

@main
struct ccInfoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appDelegate.appState)
        } label: {
            MenuBarLabel()
                .environment(appDelegate.appState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(appDelegate.appState)
                .environmentObject(appDelegate.updateService)
        }

        Window(String(localized: "Sign in to Claude"), id: "auth") {
            AuthWebView()
                .environment(appDelegate.appState)
        }
        .windowResizability(.contentSize)
    }
}

struct MenuBarLabel: View {
    @Environment(AppState.self) var appState
    @Environment(\.openWindow) private var openWindow
    @State private var cachedImage: NSImage?
    @State private var cachedKey: MenuBarCacheKey?

    var body: some View {
        let key = currentKey
        Image(nsImage: image(for: key))
            .onChange(of: key, initial: true) { _, newKey in
                cachedKey = newKey
                cachedImage = renderedImage(for: newKey)
            }
            .onChange(of: appState.showingAuth, initial: true) { _, showAuth in
                if showAuth {
                    openWindow(id: "auth")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
    }

    private var currentKey: MenuBarCacheKey? {
        guard appState.isAuthenticated, appState.usageData != nil else { return nil }
        let slot1 = appState.menuBarSlot1
        let slot2 = appState.menuBarSlot2
        let slot1Value = Int(appState.utilizationForSlot(slot1) ?? 0)
        let slot2Value = Int(appState.utilizationForSlot(slot2) ?? 0)
        let showFlame = appState.usageData.flatMap { usage in
            BurnRateCalculator.predict(
                history: appState.usageHistory,
                currentUtilization: usage.fiveHour.utilization,
                resetsAt: usage.fiveHour.resetsAt
            )
        } != nil
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return MenuBarCacheKey(slot1: slot1, slot2: slot2, value1: slot1Value, value2: slot2Value, showFlame: showFlame, isDark: isDark)
    }

    private func image(for key: MenuBarCacheKey?) -> NSImage {
        if key == cachedKey, let cached = cachedImage { return cached }
        return renderedImage(for: key)
    }

    private func renderedImage(for key: MenuBarCacheKey?) -> NSImage {
        guard let key else { return Self.fallbackImage }
        return key.showFlame
            ? MenuBarImageRenderer.renderWithFlame(
                topRow: Double(key.value1), bottomRow: Double(key.value2),
                topSlot: key.slot1, bottomSlot: key.slot2)
            : MenuBarImageRenderer.render(
                topRow: Double(key.value1), bottomRow: Double(key.value2),
                topSlot: key.slot1, bottomSlot: key.slot2)
    }

    private static let fallbackImage: NSImage = {
        let img = NSImage(systemSymbolName: "gauge.with.dots.needle.bottom.50percent",
                          accessibilityDescription: nil) ?? NSImage()
        img.isTemplate = true
        return img
    }()
}

private struct MenuBarCacheKey: Equatable, Hashable {
    let slot1: MenuBarSlot
    let slot2: MenuBarSlot
    let value1: Int
    let value2: Int
    let showFlame: Bool
    let isDark: Bool
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

    static func renderWithFlame(topRow: Double, bottomRow: Double, topSlot: MenuBarSlot = .fiveHour, bottomSlot: MenuBarSlot = .weeklyLimit) -> NSImage {
        let flameSize: CGFloat = Layout.height
        let flameGap: CGFloat = 5
        let totalWidth = flameSize + flameGap + Layout.width
        let size = NSSize(width: totalWidth, height: Layout.height)

        let image = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return true }

            // Draw flame symbol adapting to menu bar appearance (white in dark mode, black in light)
            if let flameImage = NSImage(systemSymbolName: "flame.fill", accessibilityDescription: nil) {
                let isDark = NSAppearance.currentDrawing().bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                let flameColor: NSColor = isDark ? .white : .black
                let config = NSImage.SymbolConfiguration(pointSize: flameSize * 0.75, weight: .medium)
                    .applying(.init(paletteColors: [flameColor]))
                let configured = flameImage.withSymbolConfiguration(config) ?? flameImage
                let flameRect = NSRect(x: 0, y: 0, width: flameSize, height: flameSize)
                configured.draw(in: flameRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            }

            // Shift bars to the right
            ctx.saveGState()
            ctx.translateBy(x: flameSize + flameGap, y: 0)
            drawRow(value: topRow, y: Layout.height - Layout.rowHeight, slot: topSlot)
            drawRow(value: bottomRow, y: 0, slot: bottomSlot)
            ctx.restoreGState()

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

