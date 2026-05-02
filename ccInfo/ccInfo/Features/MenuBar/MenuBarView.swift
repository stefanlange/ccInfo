import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) var appState
    @Environment(\.openWindow) private var openWindow

    @State private var showLoading = false
    @State private var clearLoadingTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if appState.isAuthenticated {
                if let errorMessage = visibleErrorMessage {
                    ErrorBanner(message: errorMessage) {
                        Task { await appState.refreshAll() }
                    }
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
                        HStack {
                            Text("5-Hour Window")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            Spacer()
                            ShareChartButton(
                                dataPoints: appState.usageHistory,
                                utilization: usage.fiveHour.utilization,
                                resetsAt: usage.fiveHour.resetsAt,
                                resetTimeFormatted: usage.fiveHour.formattedTimeUntilReset
                            )
                            .frame(width: 20, height: 16)
                        }
                        UsageChartView(dataPoints: appState.usageHistory, resetsAt: usage.fiveHour.resetsAt)
                        HStack {
                            Text("\(Int(usage.fiveHour.utilization))%")
                                .font(.system(.title2, design: .rounded, weight: .semibold))
                            Spacer()
                            if let t = usage.fiveHour.formattedTimeUntilReset {
                                VStack(alignment: .trailing, spacing: 2) {
                                    Label(t, systemImage: "clock")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if let d = usage.fiveHour.formattedResetDate {
                                        Text(d)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                        if let prediction = BurnRateCalculator.predict(
                            history: appState.usageHistory,
                            currentUtilization: usage.fiveHour.utilization,
                            resetsAt: usage.fiveHour.resetsAt
                        ) {
                            BurnRateWarningBanner(prediction: prediction)
                        }
                    }
                    Divider()
                    // Note: string also used in NotificationService.swift and MenuBarConfiguration.swift.
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
                    Image(systemName: "person.crop.circle.badge.questionmark").font(.largeTitle).foregroundStyle(.secondary)
                    Text("Not signed in").font(.callout)
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
    }
    
    private var visibleErrorMessage: String? {
        guard let err = appState.error else { return nil }
        if let apiErr = err as? ClaudeAPIClient.APIError, case .sessionExpired = apiErr {
            return nil
        }
        return err.localizedDescription
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
        HStack {
            Button { Task { await appState.refreshAll() } } label: {
                Group {
                    if showLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .buttonStyle(.borderless)
            .disabled(appState.isLoading)
            .help(String(localized: "Refresh"))
            .accessibilityLabel(showLoading ? Text("Loading") : Text("Refresh"))
            .onChange(of: appState.isLoading) { _, newValue in
                if newValue {
                    clearLoadingTask?.cancel()
                    showLoading = true
                } else {
                    clearLoadingTask = Task { [weak appState] in
                        do {
                            try await Task.sleep(for: .milliseconds(250))
                            if appState?.isLoading == false {
                                showLoading = false
                            }
                        } catch {
                            // Cancelled — a new loading phase started, leave showLoading alone.
                        }
                    }
                }
            }

            Spacer()

            SettingsLink {
                Image(systemName: "gear")
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Settings"))
            .accessibilityLabel(Text("Settings"))

            Spacer()

            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Quit"))
            .accessibilityLabel(Text("Quit"))
        }.font(.callout)
    }
}

private struct ErrorBanner: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        Button(action: retry) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.white)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(.white.opacity(0.85))
                    .font(.caption2)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.orange)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(String(localized: "Tap to retry"))
        .accessibilityLabel(String(localized: "Error: \(message)"))
        .accessibilityHint(String(localized: "Tap to retry"))
    }
}

private struct BurnRateWarningBanner: View {
    let prediction: BurnRateCalculator.Prediction

    var body: some View {
        let timeLabel = prediction.formattedTimeUntilLimit
        HStack(spacing: Spacing.xs) {
            Image(systemName: "flame.fill")
                .foregroundStyle(.white)
            Text("Token limit reached in \(timeLabel)")
                .font(.caption)
                .foregroundStyle(.white)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.red)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .font(.caption)
        .accessibilityLabel(String(localized: "Warning: projected to hit usage limit in \(timeLabel)"))
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
                Text("Context Window").font(.caption).foregroundStyle(.secondary).textCase(.uppercase)
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
                        .padding(.horizontal, Spacing.xs)
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
            Grid(
                alignment: .leading,
                horizontalSpacing: Spacing.md,
                verticalSpacing: Spacing.xs
            ) {
                GridRow {
                    Text("Models:").foregroundStyle(.secondary)
                    Text(formatModelList())
                        .gridColumnAlignment(.trailing)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                Divider()
                GridRow {
                    Text("Input:").foregroundStyle(.secondary)
                    Text(formatTokens(session.tokens.input))
                        .gridColumnAlignment(.trailing)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                GridRow {
                    Text("Output:").foregroundStyle(.secondary)
                    Text(formatTokens(session.tokens.output))
                        .gridColumnAlignment(.trailing)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                GridRow {
                    Text("Cache Write:").foregroundStyle(.secondary)
                    Text(formatTokens(session.tokens.cacheCreation))
                        .gridColumnAlignment(.trailing)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                GridRow {
                    Text("Cache Read:").foregroundStyle(.secondary)
                    Text(formatTokens(session.tokens.cacheRead))
                        .gridColumnAlignment(.trailing)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                Divider()
                GridRow {
                    Text("Total:").foregroundStyle(.secondary).fontWeight(.medium)
                    Text(formatTokens(session.tokens.totalTokens))
                        .gridColumnAlignment(.trailing)
                        .monospacedDigit()
                        .fontWeight(.medium)
                }
                .accessibilityElement(children: .combine)
                GridRow {
                    Text("Cost (API eq.):").foregroundStyle(.secondary)
                    HStack(spacing: 2) {
                        if session.isCostEstimated && session.estimatedCost > 0 {
                            Text(verbatim: "~")
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
                        .padding(.horizontal, Spacing.xs)
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
            Text("Context Window")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            ProgressView(value: 0, total: 100)
                .progressViewStyle(ColoredBarProgressStyle(
                    color: UtilizationThresholds.color(for: 0)))
                .accessibilityLabel("Context window")
                .accessibilityValue("0 %")
            HStack {
                Text(verbatim: "0%")
                    .font(.system(.title2, design: .rounded, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("No active session")
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

    @Environment(AppState.self) private var appState

    @AppStorage(AppStorageKeys.sessionActivityThreshold)
    private var sessionActivityThreshold: Double = AppStorageKeys.Defaults.sessionActivityThreshold

    @State private var editingSlug: String?
    @State private var draftName: String = ""

    private var thresholdMinutes: Int {
        Int(sessionActivityThreshold / 60)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Active Sessions")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: Spacing.sm) {
                Picker("", selection: $selectedURL) {
                    ForEach(sessions) { session in
                        Group {
                            if session.isActive {
                                Text(appState.displayName(for: session))
                            } else {
                                Text("\(appState.displayName(for: session)) (\(String(localized: "Inactive")))")
                            }
                        }
                        .help(helpText(for: session))
                        .tag(Optional(session.sessionURL))
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .accessibilityLabel("Select active session")

                Button {
                    guard let slug = currentSlug else { return }
                    draftName = appState.customSessionNameStore.customName(for: slug) ?? ""
                    editingSlug = slug
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .disabled(sessions.isEmpty || selectedURL == nil)
                .help(String(localized: "Rename session"))
                .accessibilityLabel(String(localized: "Rename session"))
                .popover(
                    item: Binding(
                        get: { editingSlug.map { IdentifiableSlug(id: $0) } },
                        set: { editingSlug = $0?.id }
                    ),
                    arrowEdge: .trailing
                ) { wrapper in
                    RenamePopoverContent(
                        slug: wrapper.id,
                        resolvedDefault: resolvedDefault(for: wrapper.id),
                        projectPath: projectPath(for: wrapper.id),
                        draftName: $draftName,
                        hasPersistedCustomName: appState.customSessionNameStore.customName(for: wrapper.id) != nil,
                        onSave: { save(slug: wrapper.id) },
                        onCancel: { cancel() },
                        onReset: { reset(slug: wrapper.id) }
                    )
                    .frame(minWidth: 280, maxWidth: 360)
                }
            }
        }
    }

    private func resolvedDefault(for slug: String) -> String {
        sessions.first(where: { $0.projectDirectory == slug })
            .map { appState.displayName(for: $0) } ?? slug
    }

    private func projectPath(for slug: String) -> String? {
        sessions.first(where: { $0.projectDirectory == slug })?.projectPath
    }

    /// Persists the draft via the shared rename model. Trim + clear-on-empty live
    /// in the store (D-09 / SESSION-NAME-06), so the surface contract is identical
    /// to the Settings → Sessions tab.
    private func save(slug: String) {
        appState.sessionRenameModel.commit(draftName, for: slug)
        editingSlug = nil
    }

    /// Discards the draft and closes the popover (no auto-save on dismiss).
    private func cancel() {
        editingSlug = nil
    }

    /// Clears any persisted custom name for the slug and immediately closes the popover.
    /// No confirmation dialog (Cancel is the undo granularity for the draft;
    /// Reset is a deliberate, visually distinct click).
    private func reset(slug: String) {
        appState.sessionRenameModel.reset(slug: slug)
        editingSlug = nil
    }

    private func helpText(for session: ActiveSession) -> String {
        let path = session.projectPath ?? session.projectDirectory
        if session.isActive {
            return path
        } else {
            return String(localized: "No activity for over \(thresholdMinutes) minutes\n\(path)")
        }
    }

    /// Wrapper that gives a session slug stable Identifiable identity for `.popover(item:)`.
    private struct IdentifiableSlug: Identifiable {
        let id: String
    }

    /// Resolves the slug of the currently selected session (nil if no selection or no match).
    private var currentSlug: String? {
        guard let url = selectedURL else { return nil }
        return sessions.first(where: { $0.sessionURL == url })?.projectDirectory
    }
}

private struct RenamePopoverContent: View {
    let slug: String
    let resolvedDefault: String
    let projectPath: String?
    @Binding var draftName: String
    let hasPersistedCustomName: Bool
    let onSave: () -> Void
    let onCancel: () -> Void
    let onReset: () -> Void

    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            LabeledContent {
                Text(slug)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            } label: {
                Text("Slug")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LabeledContent {
                Text(displayPath)
                    .font(.caption)
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            } label: {
                Text("Path")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Custom name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(resolvedDefault, text: $draftName)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFieldFocused)
                    .onSubmit { onSave() }
            }

            HStack {
                Button(role: .destructive, action: onReset) {
                    Text("Reset to Default")
                }
                .disabled(!hasPersistedCustomName)

                Spacer()

                Button("Cancel", action: onCancel)
                Button("Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Spacing.md)
        .onAppear {
            // Defer focus assignment one runloop tick — SwiftUI swallows
            // focus changes that fire mid-popover-presentation on macOS.
            DispatchQueue.main.async { nameFieldFocused = true }
        }
    }

    private var displayPath: String {
        guard let projectPath else { return slug }
        return NSString(string: projectPath).abbreviatingWithTildeInPath
    }
}

struct PeriodSwitcher: View {
    @Binding var selectedPeriod: StatisticsPeriod

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Statistics")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

        HStack(spacing: 2) { // deliberate sub-scale: tight inter-button gap for segmented-control look
            ForEach(StatisticsPeriod.allCases, id: \.self) { period in
                let isSelected = period == selectedPeriod
                Button {
                    selectedPeriod = period
                } label: {
                    Text(isSelected ? period.displayName : period.shortLabel)
                        .font(.caption2).fontWeight(isSelected ? .semibold : .regular)
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
        .padding(Spacing.xs)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .frame(maxWidth: .infinity)
        }
    }
}
