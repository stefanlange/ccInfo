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

    let keychainService = KeychainService()
    private let apiClient: ClaudeAPIClient
    private let jsonlParser = JSONLParser()
    private let logger = Logger(subsystem: "com.ccinfo.app", category: "AppState")

    init() {
        self.apiClient = ClaudeAPIClient(keychainService: keychainService)
        if let raw = UserDefaults.standard.string(forKey: "statisticsPeriod"),
           let period = StatisticsPeriod(rawValue: raw) {
            self.statisticsPeriod = period
        }
    }

    private var fileWatcher: FileWatcher?
    private var refreshTask: Task<Void, Never>?
    private var updateCheckTask: Task<Void, Never>?
    private var fileWatcherDebounceTask: Task<Void, Never>?

    private var refreshInterval: TimeInterval {
        let interval = UserDefaults.standard.double(forKey: "refreshInterval")
        return interval > 0 ? interval : 30 // Default: 30 seconds
    }

    var isAuthenticated: Bool { keychainService.hasCredentials }
    var credentials: ClaudeCredentials? { keychainService.getCredentials() }
    var contextWindow: ContextWindow? { contextWindowState?.main }

    private var sessionActivityThreshold: TimeInterval {
        let stored = UserDefaults.standard.double(forKey: "sessionActivityThreshold")
        return stored > 0 ? stored : 600 // Default: 10 minutes
    }

    var menuBarSlot1: MenuBarSlot {
        guard let raw = UserDefaults.standard.string(forKey: MenuBarConfiguration.StorageKeys.slot1),
              let slot = MenuBarSlot(rawValue: raw) else {
            return .fiveHour // fallback
        }
        return slot
    }

    var menuBarSlot2: MenuBarSlot {
        guard let raw = UserDefaults.standard.string(forKey: MenuBarConfiguration.StorageKeys.slot2),
              let slot = MenuBarSlot(rawValue: raw) else {
            return .weeklyLimit // fallback
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
                    await self?.refreshLocalData()
                }
            }
        }
        fileWatcher?.start()
    }

    func stopMonitoring() {
        refreshTask?.cancel()
        refreshTask = nil
        updateCheckTask?.cancel()
        updateCheckTask = nil
        fileWatcherDebounceTask?.cancel()
        fileWatcherDebounceTask = nil
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
            let usage = try await apiClient.fetchUsage()
            usageData = usage
            NotificationService.shared.checkThresholds(usage: usage)
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
        do {
            let availableKeys = await PricingService.shared.availableModelKeys

            // Discover active sessions
            let sessions = await jsonlParser.findActiveSessions(threshold: sessionActivityThreshold)
            activeSessions = sessions

            // Validate current selection — fall back to newest if invalid
            if selectedSessionURL == nil || !sessions.contains(where: { $0.sessionURL == selectedSessionURL }) {
                selectedSessionURL = sessions.first?.sessionURL
            }

            // Load context window and session data for selected session
            if let url = selectedSessionURL {
                contextWindowState = try await jsonlParser.getContextWindowState(for: url, availableModelKeys: availableKeys)
                sessionData = try await jsonlParser.parseForPeriod(statisticsPeriod, sessionURL: url, availableModelKeys: availableKeys)
            } else {
                contextWindowState = nil
                sessionData = try await jsonlParser.parseForPeriod(statisticsPeriod, availableModelKeys: availableKeys)
            }
        } catch {
            logger.warning("Local data error: \(error.localizedDescription)")
        }
    }

    func selectSession(_ url: URL?) {
        Task {
            guard url != selectedSessionURL else { return }
            selectedSessionURL = url
            await refreshLocalData()
        }
    }

    func updateSessionActivityThreshold() {
        Task { await refreshLocalData() }
    }

    func updateStatisticsPeriod(_ period: StatisticsPeriod) {
        statisticsPeriod = period
        UserDefaults.standard.set(period.rawValue, forKey: "statisticsPeriod")
        Task { await refreshLocalData() }
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
        showingAuth = true
    }
}
