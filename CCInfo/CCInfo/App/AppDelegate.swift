import SwiftUI
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Task {
            await NotificationService.shared.requestAuthorization()
        }
        appState.startMonitoring()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.stopMonitoring()
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var usageData: UsageData?
    @Published private(set) var sessionData: SessionData?
    @Published private(set) var contextWindowState: ContextWindowState?
    @Published private(set) var availableUpdate: AvailableUpdate?
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    @Published var showingAuth = false
    @Published var statisticsPeriod: StatisticsPeriod = .today
    @Published private(set) var pricingDataSource: PricingDataSource = .bundled
    @Published private(set) var pricingLastUpdate: Date?
    @Published private(set) var activeSessions: [ActiveSession] = []
    @Published var selectedSessionURL: URL?
    @Published private(set) var usageHistory: [UsageDataPoint] = []

    let keychainService = KeychainService()
    let usageHistoryService = UsageHistoryService()
    private let apiClient: ClaudeAPIClient
    private let jsonlParser = JSONLParser()
    private let logger = Logger(subsystem: "com.ccinfo.app", category: "AppState")

    init() {
        self.apiClient = ClaudeAPIClient(keychainService: keychainService)
        if let raw = UserDefaults.standard.string(forKey: AppStorageKeys.statisticsPeriod),
           let period = StatisticsPeriod(rawValue: raw) {
            self.statisticsPeriod = period
        }
    }

    private var fileWatcher: FileWatcher?
    private var refreshTask: Task<Void, Never>?
    private var updateCheckTask: Task<Void, Never>?
    private var fileWatcherDebounceTask: Task<Void, Never>?
    private var localDataTask: Task<Void, Never>?

    private var refreshInterval: TimeInterval {
        let interval = UserDefaults.standard.double(forKey: AppStorageKeys.refreshInterval)
        return interval > 0 ? interval : AppStorageKeys.Defaults.refreshInterval
    }

    var isAuthenticated: Bool { keychainService.hasCredentials }
    var credentials: ClaudeCredentials? { keychainService.getCredentials() }
    var contextWindow: ContextWindow? { contextWindowState?.main }

    private var sessionActivityThreshold: TimeInterval {
        let stored = UserDefaults.standard.double(forKey: AppStorageKeys.sessionActivityThreshold)
        return stored > 0 ? stored : AppStorageKeys.Defaults.sessionActivityThreshold
    }

    private func scheduleLocalDataRefresh() {
        localDataTask?.cancel()
        localDataTask = Task { await refreshLocalData() }
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
        startUpdateCheckTask()

        let home = FileManager.default.homeDirectoryForCurrentUser
        let claudePath = home.appendingPathComponent(".claude/projects").path
        fileWatcher = FileWatcher(path: claudePath) { [weak self] in
            Task { @MainActor [weak self] in
                self?.fileWatcherDebounceTask?.cancel()
                self?.fileWatcherDebounceTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled else { return }
                    self?.scheduleLocalDataRefresh()
                }
            }
        }
        fileWatcher?.start()
    }

    func stopMonitoring() {
        // Save usage history before stopping
        usageHistoryService.saveToDisk()

        refreshTask?.cancel()
        refreshTask = nil
        updateCheckTask?.cancel()
        updateCheckTask = nil
        fileWatcherDebounceTask?.cancel()
        fileWatcherDebounceTask = nil
        localDataTask?.cancel()
        localDataTask = nil
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

    private func startUpdateCheckTask() {
        updateCheckTask?.cancel()
        updateCheckTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let update = await UpdateChecker.checkForUpdate()
                self?.availableUpdate = update
                if let update {
                    NotificationService.shared.sendUpdateNotification(version: update.version)
                }
                do {
                    try await Task.sleep(for: .seconds(3600))
                } catch is CancellationError {
                    break
                } catch {
                    break
                }
            }
        }
    }

    func refreshAll() async {
        localDataTask?.cancel()
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
        let snapshotPeriod = statisticsPeriod
        let snapshotURL = selectedSessionURL

        do {
            let availableKeys = await PricingService.shared.availableModelKeys

            // Discover active sessions, falling back to the most recent session
            let sessions = await jsonlParser.findActiveSessions(threshold: sessionActivityThreshold)
            var resolvedSessions: [ActiveSession]
            if sessions.isEmpty, let mostRecent = await jsonlParser.findMostRecentSession() {
                resolvedSessions = [mostRecent]
            } else {
                resolvedSessions = sessions
            }

            // Validate current selection — fall back to newest if invalid
            var resolvedURL = snapshotURL
            if resolvedURL == nil || !sessions.contains(where: { $0.sessionURL == resolvedURL }) {
                resolvedURL = sessions.first?.sessionURL
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

            activeSessions = resolvedSessions
            selectedSessionURL = resolvedURL
            contextWindowState = newContextState
            sessionData = newSessionData
        } catch {
            logger.warning("Local data error: \(error.localizedDescription)")
        }
    }

    func selectSession(_ url: URL?) {
        guard url != selectedSessionURL else { return }
        selectedSessionURL = url
        sessionData = nil
        scheduleLocalDataRefresh()
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
        if keychainService.saveCredentials(credentials) {
            showingAuth = false
            startMonitoring()
        }
    }

    func signOut() {
        stopMonitoring()
        keychainService.deleteCredentials()
        usageData = nil
        sessionData = nil
        contextWindowState = nil
        usageHistoryService.handleWindowReset()
        usageHistory = usageHistoryService.history
        showingAuth = true
    }
}
