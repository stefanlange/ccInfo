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
    @Published private(set) var contextWindow: ContextWindow?
    @Published private(set) var availableUpdate: AvailableUpdate?
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    @Published var showingAuth = false
    @Published var statisticsPeriod: StatisticsPeriod = .today

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

    private var refreshInterval: TimeInterval {
        let interval = UserDefaults.standard.double(forKey: "refreshInterval")
        return interval > 0 ? interval : 30 // Default: 30 seconds
    }

    var isAuthenticated: Bool { keychainService.hasCredentials }
    var credentials: ClaudeCredentials? { keychainService.getCredentials() }

    func startMonitoring() {
        guard isAuthenticated else {
            showingAuth = true
            return
        }

        Task { @MainActor in await refreshAll() }
        startRefreshTask()
        startUpdateCheckTask()

        let home = FileManager.default.homeDirectoryForCurrentUser
        let claudePath = home.appendingPathComponent(".claude/projects").path
        fileWatcher = FileWatcher(path: claudePath) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.refreshLocalData()
            }
        }
        fileWatcher?.start()
    }

    func stopMonitoring() {
        refreshTask?.cancel()
        refreshTask = nil
        updateCheckTask?.cancel()
        updateCheckTask = nil
        fileWatcher?.stop()
        fileWatcher = nil
    }

    func updateRefreshInterval() {
        startRefreshTask()
    }

    private func startRefreshTask() {
        refreshTask?.cancel()

        let interval = refreshInterval
        guard interval > 0 else { return } // Manual mode - no auto-refresh

        refreshTask = Task { [weak self] in
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
        updateCheckTask = Task { [weak self] in
            // Initial check
            let update = await UpdateChecker.checkForUpdate()
            self?.availableUpdate = update

            // Repeat hourly
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(3600))
                    guard !Task.isCancelled else { break }
                    let update = await UpdateChecker.checkForUpdate()
                    self?.availableUpdate = update
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
            contextWindow = try await jsonlParser.getCurrentContextWindow()
            sessionData = try await jsonlParser.parseForPeriod(statisticsPeriod)
        } catch {
            logger.warning("Local data error: \(error.localizedDescription)")
        }
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
        contextWindow = nil
        showingAuth = true
    }
}
