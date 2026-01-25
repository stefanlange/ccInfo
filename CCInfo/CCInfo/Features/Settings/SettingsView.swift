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
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 400, height: 250)
    }
}

struct GeneralTab: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("refreshInterval") private var refreshInterval: Double = 30

    private let logger = Logger(subsystem: "com.ccinfo.app", category: "Settings")

    var body: some View {
        Form {
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
    var body: some View {
        Form {
            if appState.isAuthenticated, let creds = appState.credentials {
                LabeledContent("Status") { HStack { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green); Text("Connected") } }
                LabeledContent("Organization") { Text(creds.organizationId.prefix(8) + "...").font(.system(.body, design: .monospaced)).foregroundStyle(.secondary) }
                Section { Button("Sign out", role: .destructive) { appState.signOut() } }
            } else {
                LabeledContent("Status") { HStack { Image(systemName: "xmark.circle.fill").foregroundStyle(.red); Text("Not connected") } }
                Section { Button("Sign in") { appState.showingAuth = true }.buttonStyle(.borderedProminent) }
            }
        }.formStyle(.grouped).padding()
    }
}

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent").font(.system(size: 50)).foregroundStyle(.blue)
            Text("ccInfo").font(.title2).fontWeight(.semibold)
            Text("Know your limits. Use them wisely.").font(.subheadline).foregroundStyle(.secondary)
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")").font(.caption).foregroundStyle(.tertiary)
            Spacer()
        }.padding()
    }
}
