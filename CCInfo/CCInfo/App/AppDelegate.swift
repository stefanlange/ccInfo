import SwiftUI
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
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
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    @Published var showingAuth = false

    let keychainService = KeychainService()
    private lazy var apiClient = ClaudeAPIClient(keychainService: keychainService)
    private let jsonlParser = JSONLParser()
    private let logger = Logger(subsystem: "com.ccinfo.app", category: "AppState")

    private var fileWatcher: FileWatcher?
    private var refreshTask: Task<Void, Never>?

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

        Task { await refreshAll() }
        startRefreshTask()

        let home = FileManager.default.homeDirectoryForCurrentUser
        let claudePath = home.appendingPathComponent(".claude/projects").path
        fileWatcher = FileWatcher(path: claudePath) { [weak self] in
            Task { @MainActor in
                await self?.refreshLocalData()
            }
        }
        fileWatcher?.start()
    }

    func stopMonitoring() {
        refreshTask?.cancel()
        refreshTask = nil
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
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                await self?.refreshUsage()
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
            usageData = try await apiClient.fetchUsage()
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
            contextWindow = try jsonlParser.getCurrentContextWindow()
            if let sessionURL = jsonlParser.findLatestSession() {
                sessionData = try jsonlParser.parseSession(at: sessionURL)
            }
        } catch {
            logger.warning("Local data error: \(error.localizedDescription)")
        }
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
