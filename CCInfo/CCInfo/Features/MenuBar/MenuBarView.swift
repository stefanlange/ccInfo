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
                if appState.activeSessions.count > 1 {
                    SessionSwitcher(
                        sessions: appState.activeSessions,
                        selectedURL: sessionURLBinding
                    )
                    Divider()
                }
                if let state = appState.contextWindowState {
                    ContextSection(context: state.main)
                    if !state.activeAgents.isEmpty {
                        AgentContextList(agents: state.activeAgents)
                    }
                    Divider()
                } else {
                    EmptyContextSection()
                    Divider()
                }
                if let usage = appState.usageData {
                    // 5-Hour Window with chart
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "5-Hour Window"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        UsageChartView(dataPoints: appState.usageHistory, resetsAt: usage.fiveHour.resetsAt)
                        HStack {
                            Text("\(Int(usage.fiveHour.utilization))%")
                                .font(.system(.title2, design: .rounded, weight: .semibold))
                            Spacer()
                            if let t = usage.fiveHour.formattedTimeUntilReset {
                                Label(t, systemImage: "clock")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
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
                PeriodSwitcher(selectedPeriod: periodBinding)
                if let session = appState.sessionData {
                    SessionSection(session: session, period: appState.statisticsPeriod)
                } else {
                    HStack {
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
                Divider()
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
    
    private var sessionURLBinding: Binding<URL?> {
        Binding(
            get: { appState.selectedSessionURL },
            set: { appState.selectSession($0) }
        )
    }

    private var periodBinding: Binding<StatisticsPeriod> {
        Binding(
            get: { appState.statisticsPeriod },
            set: { appState.updateStatisticsPeriod($0) }
        )
    }

    private var footerButtons: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { Task { await appState.refreshAll() } } label: { footerLabel("Refresh", systemImage: "arrow.clockwise") }.buttonStyle(.borderless).disabled(appState.isLoading)
            SettingsLink { footerLabel("Settings", systemImage: "gear") }
                .buttonStyle(.borderless)
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
            ProgressView(value: utilization, total: 100)
                .progressViewStyle(ColoredBarProgressStyle(color: UtilizationThresholds.color(for: utilization)))
                .accessibilityLabel("\(title)")
                .accessibilityValue("\(Int(utilization)) %")
            HStack {
                Text("\(Int(utilization))%")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .accessibilityHidden(true)
                Spacer()
                if let t = resetTime {
                    VStack(alignment: .trailing, spacing: 2) {
                        Label(t, systemImage: "clock").font(.caption).foregroundStyle(.secondary)
                        if let d = resetDate {
                            Text(d).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

struct ContextSection: View {
    let context: ContextWindow

    var body: some View {
        let progressColor = UtilizationThresholds.color(for: context.utilization)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(String(localized: "Context Window")).font(.caption).foregroundStyle(.secondary).textCase(.uppercase)
                Spacer()
                if context.isNearAutoCompact {
                    Label("Near autocompact", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(progressColor)
                        .accessibilityLabel("Warning: Near autocompact threshold")
                }
            }
            ProgressView(value: context.utilization, total: 100)
                .progressViewStyle(ColoredBarProgressStyle(color: progressColor))
                .accessibilityLabel("Context window")
                .accessibilityValue("\(Int(context.utilization)) %")
            HStack {
                Text("\(Int(context.utilization))%")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .accessibilityHidden(true)
                Spacer()
                if let model = context.activeModel {
                    Text(model.displayName)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(context.badgeColor(for: model))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                        .accessibilityLabel("Model: \(model.displayName)")
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
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                GridRow {
                    Text(String(localized: "Models:")).foregroundStyle(.secondary)
                    Text(formatModelList())
                        .gridColumnAlignment(.trailing)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                Divider()
                GridRow {
                    Text(String(localized: "Input:")).foregroundStyle(.secondary)
                    Text(formatTokens(session.tokens.input))
                        .gridColumnAlignment(.trailing)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                GridRow {
                    Text(String(localized: "Output:")).foregroundStyle(.secondary)
                    Text(formatTokens(session.tokens.output))
                        .gridColumnAlignment(.trailing)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                GridRow {
                    Text(String(localized: "Cache Write:")).foregroundStyle(.secondary)
                    Text(formatTokens(session.tokens.cacheCreation))
                        .gridColumnAlignment(.trailing)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                GridRow {
                    Text(String(localized: "Cache Read:")).foregroundStyle(.secondary)
                    Text(formatTokens(session.tokens.cacheRead))
                        .gridColumnAlignment(.trailing)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                Divider()
                GridRow {
                    Text(String(localized: "Total:")).foregroundStyle(.secondary).fontWeight(.medium)
                    Text(formatTokens(session.tokens.totalTokens))
                        .gridColumnAlignment(.trailing)
                        .monospacedDigit()
                        .fontWeight(.medium)
                }
                .accessibilityElement(children: .combine)
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
                .accessibilityElement(children: .combine)
                .accessibilityHint(session.isCostEstimated && session.estimatedCost > 0 ? "Estimated based on Sonnet 4 pricing" : "")
            }.font(.caption)
        }
    }

    private func formatTokens(_ tokens: Int) -> String {
        tokens.formatted(.number.grouping(.automatic))
    }
}

struct AgentContextList: View {
    let agents: [AgentContext]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(agents) { agent in
                AgentContextRow(agent: agent)
            }
        }
        .padding(.top, 4)
        .accessibilityLabel("Active agents: \(agents.count)")
    }
}

struct AgentContextRow: View {
    let agent: AgentContext

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)

                if let model = agent.contextWindow.activeModel {
                    let color = agent.contextWindow.badgeColor(for: model)
                    Text(model.displayName)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(color)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                        .accessibilityHidden(true)
                }
            }
            .frame(width: 80, alignment: .leading)

            ProgressView(value: agent.contextWindow.utilization, total: 100)
                .progressViewStyle(ColoredBarProgressStyle(
                    color: UtilizationThresholds.color(for: agent.contextWindow.utilization)))
                .accessibilityLabel("Agent \(agent.contextWindow.activeModel?.displayName ?? "")")
                .accessibilityValue("\(Int(agent.contextWindow.utilization)) %")

            Text("\(Int(agent.contextWindow.utilization))%")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }
}

struct EmptyContextSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "Context Window"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            ProgressView(value: 0, total: 100)
                .progressViewStyle(ColoredBarProgressStyle(
                    color: UtilizationThresholds.color(for: 0)))
                .accessibilityLabel("Context window")
                .accessibilityValue("0 %")
            HStack {
                Text("0%")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(String(localized: "No active session"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        }
    }
}

struct SessionSwitcher: View {
    let sessions: [ActiveSession]
    @Binding var selectedURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "Active Sessions"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Picker("", selection: $selectedURL) {
                ForEach(sessions) { session in
                    Text(session.projectName)
                        .help(session.projectPath ?? session.projectDirectory)
                        .tag(Optional(session.sessionURL))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .accessibilityLabel("Select active session")
        }
    }
}

struct UpdateBanner: View {
    let update: AvailableUpdate

    var body: some View {
        Button {
            NSWorkspace.shared.open(update.url)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)

                Text("update.availableShort \(update.version)")
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.blue.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens download page")
    }
}

struct PeriodSwitcher: View {
    @Binding var selectedPeriod: StatisticsPeriod

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "Statistics"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

        HStack(spacing: 2) {
            ForEach(StatisticsPeriod.allCases, id: \.self) { period in
                let isSelected = period == selectedPeriod
                Button {
                    selectedPeriod = period
                } label: {
                    Text(isSelected ? period.displayName : period.shortLabel)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(period.displayName)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .frame(maxWidth: .infinity)
        }
    }
}
