import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if appState.isAuthenticated {
                if let usage = appState.usageData {
                    UsageSection(title: String(localized: "5-Hour Window"), utilization: usage.fiveHour.utilization, resetTime: usage.fiveHour.formattedTimeUntilReset)
                    Divider()
                    UsageSection(title: String(localized: "Weekly Limit"), utilization: usage.sevenDay.utilization, resetTime: usage.sevenDay.formattedTimeUntilReset, resetDate: usage.sevenDay.formattedResetDate)
                    Divider()
                    if let sonnet = usage.sevenDaySonnet {
                        UsageSection(title: String(localized: "Sonnet Weekly"), utilization: sonnet.utilization, resetTime: sonnet.formattedTimeUntilReset, resetDate: sonnet.formattedResetDate)
                        Divider()
                    }
                }
                if let ctx = appState.contextWindow {
                    ContextSection(context: ctx)
                    Divider()
                }
                if let session = appState.sessionData {
                    SessionSection(session: session)
                    Divider()
                }
                footerButtons
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.badge.questionmark").font(.system(size: 40)).foregroundStyle(.secondary)
                    Text("Not signed in").font(.headline)
                    Button("Sign in with Claude") {
                        openWindow(id: "auth")
                        NSApp.activate(ignoringOtherApps: true)
                    }.buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity).padding(.vertical)
                Divider()
                HStack {
                    Spacer()
                    Button { NSApplication.shared.terminate(nil) } label: {
                        Label("Quit", systemImage: "power")
                    }.buttonStyle(.borderless)
                }.font(.caption)
            }
        }
        .padding().frame(width: 280)
        .onChange(of: appState.showingAuth) { _, showAuth in
            if showAuth {
                openWindow(id: "auth")
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
    
    private var footerButtons: some View {
        HStack {
            Button { Task { await appState.refreshAll() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }.buttonStyle(.borderless).disabled(appState.isLoading)
            Spacer()
            SettingsLink { Label("Settings", systemImage: "gear") }
                .buttonStyle(.borderless)
                .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
            Button { NSApplication.shared.terminate(nil) } label: { Label("Quit", systemImage: "power") }.buttonStyle(.borderless)
        }.font(.caption)
    }
}

struct UsageSection: View {
    let title: String
    let utilization: Double
    let resetTime: String?
    var resetDate: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary).textCase(.uppercase)
            ProgressView(value: utilization, total: 100).tint(utilization < 50 ? .green : utilization < 80 ? .yellow : .red)
            HStack {
                Text("\(Int(utilization))%").font(.system(.title2, design: .rounded, weight: .semibold))
                Spacer()
                if let t = resetTime {
                    VStack(alignment: .trailing, spacing: 2) {
                        Label(t, systemImage: "clock").font(.caption).foregroundStyle(.secondary)
                        if let d = resetDate {
                            Text(d).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }
}

struct ContextSection: View {
    let context: ContextWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(String(localized: "Context Window")).font(.caption).foregroundStyle(.secondary).textCase(.uppercase)
                Spacer()
                if context.isNearAutoCompact { Label("Near autocompact", systemImage: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(.orange) }
            }
            ProgressView(value: context.utilization, total: 100).tint(context.isNearAutoCompact ? .orange : .blue)
            Text("\(context.currentTokens / 1000)k / \(context.maxTokens / 1000)k").font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct SessionSection: View {
    let session: SessionData
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Session Details").font(.caption).foregroundStyle(.secondary).textCase(.uppercase)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow { Text("Input:").foregroundStyle(.secondary); Text("\(session.tokens.totalInput)") }
                GridRow { Text("Output:").foregroundStyle(.secondary); Text("\(session.tokens.output)") }
                GridRow { Text("Cost (API eq.):").foregroundStyle(.secondary); Text(String(format: "$%.2f", session.tokens.estimatedCost)) }
            }.font(.caption)
        }
    }
}
