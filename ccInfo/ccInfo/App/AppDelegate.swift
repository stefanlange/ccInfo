import SwiftUI
import OSLog
import Sparkle

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, SPUStandardUserDriverDelegate {
    let appState = AppState()
    lazy var updaterController = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self)
    lazy var updateService = UpdateService(updaterController: updaterController)

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        // Bring the app to the foreground so the update dialog is visible,
        // since MenuBar-only apps have no Dock icon to click.
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {}

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UserDefaults.standard.register(defaults: [
            "SUEnableAutomaticChecks": true,
            AppStorageKeys.sonnetContextSize: AppStorageKeys.Defaults.sonnetContextSize
        ])
        try? updaterController.updater.start()
        Task {
            await NotificationService.shared.requestAuthorization()
        }
        appState.startMonitoring()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.stopMonitoring()
    }
}

@Observable @MainActor
final class AppState {
    private(set) var usageData: UsageData?
    private(set) var sessionData: SessionData?
    private(set) var contextWindowState: ContextWindowState?
    private(set) var isLoading = false
    private(set) var error: Error?
    var showingAuth = false
    var statisticsPeriod: StatisticsPeriod = .today
    private(set) var pricingDataSource: PricingDataSource = .bundled
    private(set) var pricingLastUpdate: Date?
    private(set) var activeSessions: [ActiveSession] = []
    var selectedSessionURL: URL?
    private(set) var usageHistory: [UsageDataPoint] = []

    let credentialStore = CredentialStore()
    let usageHistoryService = UsageHistoryService()
    private let apiClient: ClaudeAPIClient
    private let jsonlParser = JSONLParser()
    private let logger = Logger(subsystem: "com.ccinfo.app", category: "AppState")

    init() {
        self.apiClient = ClaudeAPIClient(credentialStore: credentialStore)
        if let raw = UserDefaults.standard.string(forKey: AppStorageKeys.statisticsPeriod),
           let period = StatisticsPeriod(rawValue: raw) {
            self.statisticsPeriod = period
        }
    }

    private var fileWatcher: FileWatcher?
    private var refreshTask: Task<Void, Never>?
    private var contextWindowTask: Task<Void, Never>?
    private var localDataTask: Task<Void, Never>?
    private var lastLocalRefresh: Date = .distantPast
    private let minLocalRefreshInterval: TimeInterval = 2.0

    private var refreshInterval: TimeInterval {
        let interval = UserDefaults.standard.double(forKey: AppStorageKeys.refreshInterval)
        return interval > 0 ? interval : AppStorageKeys.Defaults.refreshInterval
    }

    var isAuthenticated: Bool { credentialStore.hasCredentials }
    var credentials: ClaudeCredentials? { credentialStore.getCredentials() }
    var contextWindow: ContextWindow? { contextWindowState?.main }

    private var sessionActivityThreshold: TimeInterval {
        let stored = UserDefaults.standard.double(forKey: AppStorageKeys.sessionActivityThreshold)
        return stored > 0 ? stored : AppStorageKeys.Defaults.sessionActivityThreshold
    }

    private func scheduleLocalDataRefresh() {
        localDataTask?.cancel()
        localDataTask = Task { await refreshLocalData() }
    }

    private func scheduleContextWindowRefresh() {
        contextWindowTask?.cancel()
        contextWindowTask = Task { await refreshContextWindow() }
    }

    var menuBarSlot1: MenuBarSlot {
        guard let raw = UserDefaults.standard.string(forKey: AppStorageKeys.menuBarSlot1),
              let slot = MenuBarSlot(rawValue: raw) else {
            return AppStorageKeys.Defaults.menuBarSlot1
        }
        return slot
    }

    var menuBarSlot2: MenuBarSlot {
        guard let raw = UserDefaults.standard.string(forKey: AppStorageKeys.menuBarSlot2),
              let slot = MenuBarSlot(rawValue: raw) else {
            return AppStorageKeys.Defaults.menuBarSlot2
        }
        return slot
    }

    func utilizationForSlot(_ slot: MenuBarSlot) -> Double? {
        switch slot {
        case .contextWindow:
            return contextWindowState?.main.utilization
        case .fiveHour:
            return usageData?.fiveHour.utilization
        case .weeklyLimit:
            return usageData?.sevenDay.utilization
        case .sonnetWeekly:
            return usageData?.sevenDaySonnet?.utilization
        }
    }

    func startMonitoring() {
        guard isAuthenticated else {
            showingAuth = true
            return
        }

        // Load persisted usage history
        usageHistoryService.loadFromDisk()
        usageHistory = usageHistoryService.history

        // Start pricing data monitoring (fetch + 12h refresh cycle)
        Task {
            await PricingService.shared.startMonitoring()
        }

        Task { @MainActor in await refreshAll() }
        startRefreshTask()

        let home = FileManager.default.homeDirectoryForCurrentUser
        let claudePath = home.appendingPathComponent(".claude/projects").path
        fileWatcher = FileWatcher(path: claudePath) { [weak self] _ in
            // FSEventStream dispatches on DispatchQueue.main, so MainActor is safe here.
            // Using assumeIsolated avoids async Task enqueue, making the timestamp gate atomic.
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = Date()
                guard now.timeIntervalSince(self.lastLocalRefresh) >= self.minLocalRefreshInterval else { return }
                self.lastLocalRefresh = now
                self.scheduleLocalDataRefresh()
            }
        }
        fileWatcher?.start()
    }

    func stopMonitoring() {
        // Save usage history before stopping
        usageHistoryService.saveToDisk()

        refreshTask?.cancel()
        refreshTask = nil
        localDataTask?.cancel()
        localDataTask = nil
        contextWindowTask?.cancel()
        contextWindowTask = nil
        fileWatcher?.stop()
        fileWatcher = nil
        Task {
            await PricingService.shared.stopMonitoring()
        }
    }

    func updateRefreshInterval() {
        startRefreshTask()
    }

    private func startRefreshTask() {
        refreshTask?.cancel()

        let interval = refreshInterval
        guard interval > 0 else { return } // Manual mode - no auto-refresh

        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(interval))
                    guard !Task.isCancelled else { break }
                    await self?.refreshAll()
                } catch is CancellationError {
                    break
                } catch {
                    // Unexpected error - should not happen with Task.sleep
                    break
                }
            }
        }
    }

    func refreshAll() async {
        localDataTask?.cancel()
        contextWindowTask?.cancel()
        await refreshUsage()
        await refreshLocalData()
        await refreshPricingStatus()
    }

    func refreshPricingStatus() async {
        pricingDataSource = await PricingService.shared.dataSource
        pricingLastUpdate = await PricingService.shared.lastUpdateTimestamp
    }

    func refreshUsage() async {
        isLoading = true
        error = nil
        do {
            let previousUsage = usageData
            let usage = try await apiClient.fetchUsage()
            usageData = usage
            NotificationService.shared.checkThresholds(usage: usage)
            NotificationService.shared.checkBurnRate(history: usageHistoryService.history, usage: usage)

            // Record usage data point
            let percent = Int(usage.fiveHour.utilization)
            usageHistoryService.record(usagePercent: percent)
            usageHistory = usageHistoryService.history

            // Detect window reset: utilization dropped to near-zero from a meaningful level
            if let previous = previousUsage {
                let previousUtil = previous.fiveHour.utilization
                let newUtil = usage.fiveHour.utilization
                if newUtil < 5 && previousUtil > 20 {
                    logger.info("Window reset detected (prev: \(previousUtil), new: \(newUtil))")
                    usageHistoryService.handleWindowReset()
                    usageHistory = usageHistoryService.history
                }
            }
        } catch let apiError as ClaudeAPIClient.APIError {
            error = apiError
            logger.error("API error: \(apiError.localizedDescription)")
            if case .sessionExpired = apiError { showingAuth = true }
        } catch {
            self.error = error
            logger.error("Unexpected error: \(error.localizedDescription)")
        }
        isLoading = false
    }

    func refreshLocalData() async {
        guard !Task.isCancelled else { return }
        let snapshotPeriod = statisticsPeriod
        let snapshotURL = selectedSessionURL

        do {
            let availableKeys = await PricingService.shared.availableModelKeys
            guard !Task.isCancelled else { return }

            // Discover active and recently inactive sessions (single directory walk)
            let (foundSessions, fallback) = await jsonlParser.findSessionsWithFallback(threshold: sessionActivityThreshold)
            guard !Task.isCancelled else { return }
            var sessions = foundSessions.isEmpty ? (fallback.map { [$0] } ?? []) : foundSessions

            // Resolve session URL: keep current if still in list, otherwise find successor
            var resolvedURL = snapshotURL
            if let url = resolvedURL, !sessions.contains(where: { $0.sessionURL == url }) {
                // Selected session no longer in list — find newest session for the same project
                let oldProjectDir = url.deletingLastPathComponent().lastPathComponent
                resolvedURL = sessions.first(where: { $0.projectDirectory == oldProjectDir })?.sessionURL
            }
            if resolvedURL == nil {
                resolvedURL = sessions.first(where: { $0.isActive })?.sessionURL
                    ?? sessions.first?.sessionURL
            }

            // Load context window and session data for selected session
            var newContextState: ContextWindowState?
            var newSessionData: SessionData?
            if let url = resolvedURL {
                newContextState = try await jsonlParser.getContextWindowState(for: url, availableModelKeys: availableKeys)
                newSessionData = try await jsonlParser.parseForPeriod(snapshotPeriod, sessionURL: url, availableModelKeys: availableKeys)
            } else {
                newContextState = nil
                newSessionData = try await jsonlParser.parseForPeriod(snapshotPeriod, availableModelKeys: availableKeys)
            }

            // Only apply results if snapshot is still current
            guard !Task.isCancelled,
                  snapshotPeriod == statisticsPeriod,
                  snapshotURL == selectedSessionURL else { return }

            activeSessions = sessions
            selectedSessionURL = resolvedURL
            contextWindowState = newContextState
            sessionData = newSessionData
        } catch is CancellationError {
            // Expected when a newer refresh supersedes this one
        } catch {
            logger.warning("Local data error: \(error.localizedDescription)")
        }
    }

    private func refreshContextWindow() async {
        guard let url = selectedSessionURL else {
            contextWindowState = nil
            return
        }
        do {
            let availableKeys = await PricingService.shared.availableModelKeys
            let newContextState = try await jsonlParser.getContextWindowState(for: url, availableModelKeys: availableKeys)
            guard !Task.isCancelled, url == selectedSessionURL else { return }
            contextWindowState = newContextState
        } catch {
            logger.warning("Context window refresh error: \(error.localizedDescription)")
        }
    }

    func selectSession(_ url: URL?) {
        guard url != selectedSessionURL else { return }
        selectedSessionURL = url

        if statisticsPeriod == .session {
            sessionData = nil
            scheduleLocalDataRefresh()
        } else {
            scheduleContextWindowRefresh()
        }
    }

    func updateSessionActivityThreshold() {
        scheduleLocalDataRefresh()
    }

    func updateStatisticsPeriod(_ period: StatisticsPeriod) {
        statisticsPeriod = period
        UserDefaults.standard.set(period.rawValue, forKey: AppStorageKeys.statisticsPeriod)
        sessionData = nil
        scheduleLocalDataRefresh()
    }

    func signIn(credentials: ClaudeCredentials) {
        if credentialStore.saveCredentials(credentials) {
            showingAuth = false
            startMonitoring()
        }
    }

    func signOut() {
        stopMonitoring()
        credentialStore.deleteCredentials()
        usageData = nil
        sessionData = nil
        contextWindowState = nil
        usageHistoryService.handleWindowReset()
        usageHistory = usageHistoryService.history
        NotificationService.shared.resetAllThresholds()
        showingAuth = true
    }
}
