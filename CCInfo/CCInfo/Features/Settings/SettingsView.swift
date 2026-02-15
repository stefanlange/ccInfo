import SwiftUI
import ServiceManagement
import OSLog

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            GeneralTab()
                .environmentObject(appState)
                .tabItem { Label("General", systemImage: "gear") }
            AccountTab()
                .environmentObject(appState)
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
            AboutTab()
                .environmentObject(appState)
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .background(SettingsWindowAccessor())
        .frame(width: 400, height: 330)
    }
}

struct GeneralTab: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("refreshInterval") private var refreshInterval: Double = 30
    @AppStorage("sessionActivityThreshold") private var sessionActivityThreshold: Double = 600
    @AppStorage("menuBarSlot1") private var menuBarSlot1: MenuBarSlot = .fiveHour
    @AppStorage("menuBarSlot2") private var menuBarSlot2: MenuBarSlot = .weeklyLimit

    private let logger = Logger(subsystem: "com.ccinfo.app", category: "Settings")

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        updateLaunchAtLogin(enabled: enabled)
                    }

                Picker("Auto-refresh", selection: $refreshInterval) {
                    Text("Manual").tag(0.0)
                    Text("30 seconds").tag(30.0)
                    Text("1 minute").tag(60.0)
                    Text("2 minutes").tag(120.0)
                    Text("5 minutes").tag(300.0)
                    Text("10 minutes").tag(600.0)
                }
                .onChange(of: refreshInterval) { _, _ in
                    appState.updateRefreshInterval()
                }

                Picker(String(localized: "Session Activity"), selection: $sessionActivityThreshold) {
                    Text(String(localized: "5 minutes")).tag(300.0)
                    Text(String(localized: "10 minutes")).tag(600.0)
                    Text(String(localized: "30 minutes")).tag(1800.0)
                    Text(String(localized: "1 hour")).tag(3600.0)
                    Text(String(localized: "4 hours")).tag(14400.0)
                }
                .onChange(of: sessionActivityThreshold) { _, _ in
                    appState.updateSessionActivityThreshold()
                }
            }

            Section(String(localized: "MenuBar Display")) {
                Picker(String(localized: "Slot 1"), selection: $menuBarSlot1) {
                    ForEach(MenuBarSlot.allCases, id: \.self) { slot in
                        Text(slot.displayName).tag(slot)
                    }
                }
                .onChange(of: menuBarSlot1) { _, newValue in
                    if newValue == menuBarSlot2 {
                        menuBarSlot2 = MenuBarSlot.allCases.first { $0 != newValue } ?? .contextWindow
                    }
                }

                Picker(String(localized: "Slot 2"), selection: $menuBarSlot2) {
                    ForEach(MenuBarSlot.allCases, id: \.self) { slot in
                        Text(slot.displayName).tag(slot)
                    }
                }
                .onChange(of: menuBarSlot2) { _, newValue in
                    if newValue == menuBarSlot1 {
                        menuBarSlot1 = MenuBarSlot.allCases.first { $0 != newValue } ?? .contextWindow
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func updateLaunchAtLogin(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("Failed to update launch at login: \(error.localizedDescription)")
            // Revert the toggle on failure
            launchAtLogin = !enabled
        }
    }
}

struct AccountTab: View {
    @EnvironmentObject var appState: AppState
    @State private var orgIdCopied = false
    @State private var copyResetTask: Task<Void, Never>?

    var body: some View {
        Form {
            if appState.isAuthenticated, let creds = appState.credentials {
                LabeledContent(String(localized: "Status")) { HStack { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green); Text(String(localized: "Connected")) } }

                LabeledContent(String(localized: "Organization")) {
                    VStack(alignment: .trailing, spacing: 4) {
                        if let orgName = creds.organizationName {
                            Text(orgName).font(.body)
                        }

                        HStack(spacing: 6) {
                            Text(String(creds.organizationId.prefix(8)) + "...")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)

                            Button {
                                copyOrgId(creds.organizationId)
                            } label: {
                                Image(systemName: orgIdCopied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 11))
                                    .foregroundStyle(orgIdCopied ? .green : .secondary)
                            }
                            .buttonStyle(.plain)
                            .help(String(localized: "Copy Organization ID"))
                        }
                    }
                }

                Section { Button(String(localized: "Sign out"), role: .destructive) { appState.signOut() } }
            } else {
                LabeledContent(String(localized: "Status")) { HStack { Image(systemName: "xmark.circle.fill").foregroundStyle(.red); Text(String(localized: "Not connected")) } }
                Section { Button(String(localized: "Sign in")) { appState.showingAuth = true }.buttonStyle(.borderedProminent) }
            }
        }.formStyle(.grouped).padding()
    }

    private func copyOrgId(_ orgId: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(orgId, forType: .string)
        withAnimation { orgIdCopied = true }
        copyResetTask?.cancel()
        copyResetTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation { orgIdCopied = false }
        }
    }
}

struct AboutTab: View {
    @EnvironmentObject var appState: AppState

    private var versionLabel: String {
        let value = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let isVersion = value.contains(".")
        return isVersion ? String(localized: "Version \(value)") : String(localized: "Build \(value)")
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent").font(.system(size: 50)).foregroundStyle(.blue)
            Text("ccInfo").font(.title2).fontWeight(.semibold)
            Text("Know your limits. Use them wisely.").font(.subheadline).foregroundStyle(.secondary)
            Text(versionLabel).font(.caption).foregroundStyle(.tertiary)

            Divider().padding(.horizontal)

            HStack {
                Text("Pricing Data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                PricingStatusRow(
                    dataSource: appState.pricingDataSource,
                    lastUpdate: appState.pricingLastUpdate
                )
            }
            .padding(.horizontal)

            Spacer()
        }.padding()
    }
}

struct PricingStatusRow: View {
    let dataSource: PricingDataSource
    let lastUpdate: Date?

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(statusLabel)
                .font(.caption)

            if let lastUpdate {
                Text("— \(relativeTime(for: lastUpdate))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusColor: Color {
        switch dataSource {
        case .live: return .green
        case .cached: return .yellow
        case .bundled: return .gray
        }
    }

    private var statusLabel: String {
        switch dataSource {
        case .live: return String(localized: "Live")
        case .cached: return String(localized: "Cached")
        case .bundled: return String(localized: "Bundled")
        }
    }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    private func relativeTime(for date: Date) -> String {
        Self.relativeDateFormatter.localizedString(for: date, relativeTo: .now)
    }
}

private struct SettingsWindowAccessor: NSViewRepresentable {
    final class Coordinator {
        var observer: Any?
        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            Self.centerOnMouseScreen(window)
            Self.activateAboveAllWindows(window)

            // Observe every subsequent window open
            context.coordinator.observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: window,
                queue: .main
            ) { notification in
                guard let window = notification.object as? NSWindow else { return }
                Self.centerOnMouseScreen(window)
                Self.activateAboveAllWindows(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            Self.activateAboveAllWindows(window)
        }
    }

    /// Bring window above all other windows, then reset to normal level
    private static func activateAboveAllWindows(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.level = .floating
        window.makeKeyAndOrderFront(nil)
        // Reset to normal level so the window can be covered by other windows later
        DispatchQueue.main.async {
            window.level = .normal
        }
    }

    /// Center window on the screen where the mouse cursor is located
    private static func centerOnMouseScreen(_ window: NSWindow) {
        let mouseLocation = NSEvent.mouseLocation
        guard let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) else { return }

        let screenFrame = targetScreen.visibleFrame
        let windowSize = window.frame.size
        let x = screenFrame.midX - windowSize.width / 2
        let y = screenFrame.midY - windowSize.height / 2
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
