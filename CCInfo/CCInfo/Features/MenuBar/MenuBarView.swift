import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if appState.isAuthenticated {
                if let update = appState.availableUpdate {
                    UpdateBanner(update: update)
                    Divider()
                }
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
                    SessionSection(session: session, period: appState.statisticsPeriod)
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
            Button { Task { await appState.refreshAll() } } label: { footerLabel("Refresh", systemImage: "arrow.clockwise") }.buttonStyle(.borderless).disabled(appState.isLoading)
            SettingsLink { footerLabel("Settings", systemImage: "gear") }
                .buttonStyle(.borderless)
                .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
            Button { NSApplication.shared.terminate(nil) } label: { footerLabel("Quit", systemImage: "power") }.buttonStyle(.borderless)
        }.font(.callout)
    }

    private func footerLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage).frame(width: 16, alignment: .center)
            Text(title)
        }
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

    private func modelBadgeColor(for model: ModelIdentifier) -> Color {
        switch model.family {
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
                    Text(model.displayName)
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
    let period: StatisticsPeriod

    private var sortedModels: [ModelIdentifier] {
        let tierOrder: [ClaudeModel: Int] = [.opus: 0, .sonnet: 1, .haiku: 2, .unknown: 3]
        return session.models.sorted { a, b in
            let aTier = tierOrder[a.family] ?? 999
            let bTier = tierOrder[b.family] ?? 999
            if aTier != bTier { return aTier < bTier }
            return a.displayName < b.displayName
        }
    }

    private func formatModelList() -> String {
        sortedModels
            .filter { $0.family != .unknown }
            .map { $0.displayName }
            .joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(period.displayName)
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
                    HStack(spacing: 2) {
                        if session.isCostEstimated && session.estimatedCost > 0 {
                            Text("~")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(session.estimatedCost.formattedCurrency())
                            .monospacedDigit()
                    }
                    .gridColumnAlignment(.trailing)
                    .help(session.isCostEstimated && session.estimatedCost > 0
                        ? String(localized: "Estimated (Sonnet 4 Pricing) \u{2014} model not in pricing database")
                        : "")
                }
            }.font(.caption)
        }
    }

    private func formatTokens(_ tokens: Int) -> String {
        tokens.formatted(.number.grouping(.automatic))
    }
}

struct UpdateBanner: View {
    let update: AvailableUpdate

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    var body: some View {
        Button {
            NSWorkspace.shared.open(update.url)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("update.available \(update.version)")
                    Text("update.currentVersion \(currentVersion)")
                    Text("update.download")
                }
                .font(.caption)
                .multilineTextAlignment(.leading)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.blue.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}
