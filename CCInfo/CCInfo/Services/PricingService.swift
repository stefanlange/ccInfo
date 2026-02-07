import Foundation
import OSLog

actor PricingService {
    static let shared = PricingService()

    private var pricingData: [String: ModelPricing]?
    private(set) var dataSource: PricingDataSource = .bundled
    private let logger = Logger(subsystem: "com.ccinfo.app", category: "PricingService")
    private var refreshTask: Task<Void, Never>?

    private init() {
        // Non-blocking init: load bundled data synchronously (milliseconds, safe)
        // Uses static method to avoid actor-isolation warnings in nonisolated init
        self.pricingData = Self.loadBundledData(logger: logger)
        // dataSource defaults to .bundled via property initializer
        // Background fetch started separately via startMonitoring()
    }

    // MARK: - Public API

    /// Returns pricing for the specified model ID, with Sonnet fallback if not found
    func pricing(for modelId: String) -> ModelPricing {
        // Try exact match first
        if let pricing = pricingData?[modelId] {
            return pricing
        }

        // Try lowercase match
        if let pricing = pricingData?[modelId.lowercased()] {
            return pricing
        }

        // Fallback to Sonnet default
        logger.debug("Model '\(modelId)' not found in pricing data, using Sonnet default")
        return ModelPricing.sonnetDefault
    }

    /// Start periodic monitoring: fetch immediately, then refresh every 12h
    func startMonitoring() {
        // Cancel any existing task
        refreshTask?.cancel()

        refreshTask = Task {
            // Immediate refresh on startup
            await refreshPricingData()

            // Start periodic refresh
            await startPeriodicRefresh()
        }
    }

    /// Stop periodic monitoring
    func stopMonitoring() {
        refreshTask?.cancel()
        refreshTask = nil
        logger.info("Stopped pricing data monitoring")
    }

    /// Force immediate refresh (for manual refresh button)
    func forceRefresh() async {
        logger.info("Force refresh requested")
        await refreshPricingData()
    }

    // MARK: - Private Methods

    /// Load bundled fallback JSON from app bundle
    /// Static + nonisolated to allow calling from actor init without isolation warnings
    private nonisolated static func loadBundledData(logger: Logger) -> [String: ModelPricing]? {
        guard let url = Bundle.main.url(forResource: "claude-pricing-fallback", withExtension: "json") else {
            logger.warning("No bundled pricing fallback found")
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let rawData = try decoder.decode([String: LiteLLMModel].self, from: data)
            let claudeModels = rawData.filter { key, _ in key.lowercased().contains("claude") }
            let converted = claudeModels.mapValues { ModelPricing(from: $0) }
            logger.info("Loaded \(converted.count) models from bundled fallback")
            return converted
        } catch {
            logger.error("Failed to load bundled pricing data: \(error.localizedDescription)")
            return nil
        }
    }

    /// Refresh pricing data with fallback chain: Cache (if fresh) -> Network -> Cache (stale) -> Bundled
    private func refreshPricingData() async {
        // Step 1: Check cache staleness
        let cacheStale = isCacheStale()

        // If cache exists and is fresh, load and use it
        if !cacheStale, let cached = loadCachedData() {
            pricingData = cached
            dataSource = .cached
            logger.info("Loaded \(cached.count) models from fresh cache")
            return
        }

        // Step 2: Try network fetch
        do {
            let fetched = try await fetchFromNetwork()
            pricingData = fetched
            dataSource = .live
            saveCachedData(fetched)
            logger.info("Fetched \(fetched.count) models from network, cache updated")
            return
        } catch {
            logger.warning("Network fetch failed: \(error.localizedDescription)")
        }

        // Step 3: Fall back to stale cache if available
        if let cached = loadCachedData() {
            pricingData = cached
            dataSource = .cached
            logger.warning("Using stale cache (\(cached.count) models) after network failure")
            return
        }

        // Step 4: Keep bundled data (already loaded in init)
        logger.warning("Network and cache unavailable, keeping bundled data")
    }

    /// Fetch pricing data from LiteLLM GitHub with timeout and retry
    private func fetchFromNetwork() async throws -> [String: ModelPricing] {
        let urlString = "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"

        guard let url = URL(string: urlString) else {
            throw PricingError.networkError(URLError(.badURL))
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15

        // First attempt
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw PricingError.networkError(URLError(.badServerResponse))
            }

            guard http.statusCode == 200 else {
                throw PricingError.httpError(http.statusCode)
            }

            return try parsePricingData(data)
        } catch {
            logger.warning("First fetch attempt failed: \(error.localizedDescription), retrying in 5s...")

            // Check cancellation before retry
            if Task.isCancelled {
                throw CancellationError()
            }

            // Wait 5 seconds before retry
            try await Task.sleep(for: .seconds(5))

            // Check cancellation after sleep
            if Task.isCancelled {
                throw CancellationError()
            }

            // Second attempt
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw PricingError.networkError(URLError(.badServerResponse))
            }

            guard http.statusCode == 200 else {
                throw PricingError.httpError(http.statusCode)
            }

            return try parsePricingData(data)
        }
    }

    /// Parse raw LiteLLM JSON data, filtering to Claude models only
    private func parsePricingData(_ data: Data) throws -> [String: ModelPricing] {
        do {
            let decoder = JSONDecoder()
            let rawData = try decoder.decode([String: LiteLLMModel].self, from: data)

            // Filter to Claude models only (keys containing "claude", case-insensitive)
            let claudeModels = rawData.filter { key, _ in
                key.lowercased().contains("claude")
            }

            // Convert to ModelPricing
            let converted = claudeModels.mapValues { ModelPricing(from: $0) }

            logger.info("Parsed \(converted.count) Claude model prices from LiteLLM data (filtered from \(rawData.count) total)")
            return converted
        } catch {
            logger.error("Failed to parse pricing data: \(error.localizedDescription)")
            throw PricingError.parseError(error)
        }
    }

    /// Load cached pricing data from Application Support
    private func loadCachedData() -> [String: ModelPricing]? {
        do {
            let cacheURL = try cacheFileURL()
            guard FileManager.default.fileExists(atPath: cacheURL.path) else {
                return nil
            }

            let data = try Data(contentsOf: cacheURL)
            let decoded = try JSONDecoder().decode([String: ModelPricing].self, from: data)
            return decoded
        } catch let error as DecodingError {
            // Corrupt cache - delete it
            logger.error("Cache file corrupt, deleting: \(error.localizedDescription)")
            if let url = try? cacheFileURL() {
                try? FileManager.default.removeItem(at: url)
            }
            return nil
        } catch {
            return nil
        }
    }

    /// Save pricing data to Application Support cache
    private func saveCachedData(_ data: [String: ModelPricing]) {
        do {
            let cacheURL = try cacheFileURL()

            // Create intermediate directories if needed
            let directory = cacheURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let encoded = try JSONEncoder().encode(data)
            try encoded.write(to: cacheURL, options: .atomic)
            logger.info("Saved \(data.count) models to cache")
        } catch {
            logger.error("Failed to save cache: \(error.localizedDescription)")
        }
    }

    /// Get cache file URL in Application Support
    private func cacheFileURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport
            .appendingPathComponent("com.ccinfo.app", isDirectory: true)
            .appendingPathComponent("pricing-cache.json")
    }

    /// Check if cache is stale (> 12 hours old)
    private func isCacheStale() -> Bool {
        do {
            let cacheURL = try cacheFileURL()
            let attributes = try FileManager.default.attributesOfItem(atPath: cacheURL.path)
            guard let modificationDate = attributes[.modificationDate] as? Date else {
                return true
            }

            let age = Date().timeIntervalSince(modificationDate)
            let stale = age > 43200 // 12 hours in seconds
            if stale {
                logger.debug("Cache is stale (age: \(Int(age/3600))h)")
            }
            return stale
        } catch {
            // File doesn't exist or can't read attributes
            return true
        }
    }

    /// Start periodic refresh every 12 hours
    private func startPeriodicRefresh() async {
        while !Task.isCancelled {
            do {
                // Sleep for 12 hours
                try await Task.sleep(for: .seconds(43200))

                // Check cancellation after sleep
                guard !Task.isCancelled else {
                    break
                }

                // Refresh data
                await refreshPricingData()
            } catch {
                // Task was cancelled during sleep
                break
            }
        }
    }
}
