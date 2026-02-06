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
                    if let opus = usage.sevenDayOpus {
                        UsageSection(title: String(localized: "Opus Weekly"), utilization: opus.utilization, resetTime: opus.formattedTimeUntilReset, resetDate: opus.formattedResetDate)
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
        VStack(alignment: .leading, spacing: 10) {
            Button { Task { await appState.refreshAll() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }.buttonStyle(.borderless).disabled(appState.isLoading)
            SettingsLink { Label("Settings", systemImage: "gear") }
                .buttonStyle(.borderless)
                .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
            Button { NSApplication.shared.terminate(nil) } label: { Label("Quit", systemImage: "power") }.buttonStyle(.borderless)
        }.font(.callout)
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

    private var barColor: Color {
        if context.isNearAutoCompact {
            return .orange
        }
        let utilization = context.utilization
        if utilization < 50 {
            return .green
        } else if utilization < 75 {
            return .yellow
        } else {
            return .orange
        }
    }

    private var maxTokensFormatted: String {
        if context.maxTokens >= 1_000_000 {
            return "1M"
        } else {
            return "\(context.maxTokens / 1000)k"
        }
    }

    private func modelBadgeColor(for model: ClaudeModel) -> Color {
        switch model {
        case .opus: return .purple
        case .sonnet: return context.isExtendedContext ? .red : .orange
        case .haiku: return .cyan
        case .unknown: return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(String(localized: "Context Window")).font(.caption).foregroundStyle(.secondary).textCase(.uppercase)
                Spacer()
                if context.isNearAutoCompact { Label("Near autocompact", systemImage: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(.orange) }
            }
            ProgressView(value: context.utilization, total: 100).tint(barColor)
            HStack {
                Text("\(context.currentTokens / 1000)k / \(maxTokensFormatted)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let model = context.activeModel {
                    Text(model.displayName(extended: context.isExtendedContext))
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(modelBadgeColor(for: model).opacity(0.2))
                        .foregroundStyle(modelBadgeColor(for: model))
                        .clipShape(Capsule())
                }
            }
        }
    }
}

struct SessionSection: View {
    let session: SessionData

    private var sortedModels: [ClaudeModel] {
        session.models.sorted { $0.displayName < $1.displayName }
    }

    private func formatModelList() -> String {
        sortedModels
            .filter { $0 != .unknown }
            .map { $0.displayName }
            .joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "Session Details"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                GridRow {
                    Text(String(localized: "Models:")).foregroundStyle(.secondary)
                    Text(formatModelList())
                        .gridColumnAlignment(.trailing)
                        .monospacedDigit()
                }
                Divider()
                GridRow {
                    Text(String(localized: "Input:")).foregroundStyle(.secondary)
                    Text(formatTokens(session.tokens.input))
                        .gridColumnAlignment(.trailing)
                        .monospacedDigit()
                }
                GridRow {
                    Text(String(localized: "Output:")).foregroundStyle(.secondary)
                    Text(formatTokens(session.tokens.output))
                        .gridColumnAlignment(.trailing)
                        .monospacedDigit()
                }
                GridRow {
                    Text(String(localized: "Cache Write:")).foregroundStyle(.secondary)
                    Text(formatTokens(session.tokens.cacheCreation))
                        .gridColumnAlignment(.trailing)
                        .monospacedDigit()
                }
                GridRow {
                    Text(String(localized: "Cache Read:")).foregroundStyle(.secondary)
                    Text(formatTokens(session.tokens.cacheRead))
                        .gridColumnAlignment(.trailing)
                        .monospacedDigit()
                }
                Divider()
                GridRow {
                    Text(String(localized: "Total:")).foregroundStyle(.secondary).fontWeight(.medium)
                    Text(formatTokens(session.tokens.totalTokens))
                        .gridColumnAlignment(.trailing)
                        .monospacedDigit()
                        .fontWeight(.medium)
                }
                GridRow {
                    Text(String(localized: "Cost (API eq.):")).foregroundStyle(.secondary)
                    Text(String(format: "$%.2f", session.estimatedCost))
                        .gridColumnAlignment(.trailing)
                        .monospacedDigit()
                }
            }.font(.caption)
        }
    }

    private func formatTokens(_ tokens: Int) -> String {
        tokens.formatted(.number.grouping(.automatic))
    }
}
