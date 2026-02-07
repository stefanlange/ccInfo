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

            Picker(String(localized: "Statistics"), selection: periodBinding) {
                ForEach(StatisticsPeriod.allCases, id: \.self) { period in
                    Text(period.displayName).tag(period)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var periodBinding: Binding<StatisticsPeriod> {
        Binding(
            get: { appState.statisticsPeriod },
            set: { appState.updateStatisticsPeriod($0) }
        )
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

        withAnimation {
            orgIdCopied = true
        }

        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation {
                orgIdCopied = false
            }
        }
    }
}

struct AboutTab: View {
    @EnvironmentObject var appState: AppState

    private var versionLabel: String {
        let value = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let isVersion = value.contains(".")
        return isVersion ? "Version \(value)" : "Build \(value)"
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
        case .live: return "Live"
        case .cached: return "Cached"
        case .bundled: return "Bundled"
        }
    }

    private func relativeTime(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}
