import Foundation
import OSLog

actor JSONLParser {
    private let claudeProjectsPath: URL
    private let decoder: JSONDecoder
    private let pricingService: PricingService
    private let logger = Logger(subsystem: "com.ccinfo.app", category: "JSONLParser")

    init(pricingService: PricingService = .shared) {
        self.pricingService = pricingService
        claudeProjectsPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }
    
    // MARK: - Token Accumulator

    /// Encapsulates token accumulation state to eliminate duplication across parsing methods
    private struct TokenAccumulator {
        var totalInput = 0
        var totalOutput = 0
        var totalCacheCreation = 0
        var totalCacheRead = 0
        var totalCost = 0.0
        var models: Set<ModelIdentifier> = []
        var processedHashes: Set<String> = []
        var cumulativeInputByModel: [String: Int] = [:]

        /// Check if an entry should be processed (dedup + usage filter + synthetic skip).
        /// Registers the hash as a side effect if the entry passes.
        mutating func shouldProcess(_ entry: JSONLEntry) -> JSONLEntry.TokenUsage? {
            if let hash = entry.uniqueHash {
                if processedHashes.contains(hash) { return nil }
                processedHashes.insert(hash)
            }
            guard let usage = entry.message?.usage else { return nil }
            if entry.rawModelId == "<synthetic>" { return nil }
            return usage
        }

        /// Get cumulative input tokens for a model (needed for tiered pricing)
        func cumulativeInput(for rawModelId: String?) -> Int {
            cumulativeInputByModel[rawModelId ?? ""] ?? 0
        }

        /// Accumulate tokens and cost for a validated entry
        mutating func accumulate(
            usage: JSONLEntry.TokenUsage,
            rawModelId: String?,
            entryCost: Double,
            entryModel: ModelIdentifier?
        ) {
            totalInput += usage.inputTokens ?? 0
            totalOutput += usage.outputTokens ?? 0
            totalCacheCreation += usage.cacheCreationInputTokens ?? 0
            totalCacheRead += usage.cacheReadInputTokens ?? 0
            totalCost += entryCost
            if let m = entryModel { models.insert(m) }

            let modelKey = rawModelId ?? ""
            let inputIncrement = (usage.inputTokens ?? 0)
                + (usage.cacheCreationInputTokens ?? 0)
                + (usage.cacheReadInputTokens ?? 0)
            cumulativeInputByModel[modelKey, default: 0] += inputIncrement
        }

        /// Build the final TokenStats from accumulated values
        func buildTokenStats() -> SessionData.TokenStats {
            SessionData.TokenStats(
                input: totalInput,
                output: totalOutput,
                cacheCreation: totalCacheCreation,
                cacheRead: totalCacheRead,
                cost: totalCost
            )
        }
    }

    // MARK: - Private Methods

    /// Calculate cost for a single entry, using costUSD if available, falling back to token-based pricing
    private func costForEntry(
        costUSD: Double?,
        rawModelId: String?,
        usage: JSONLEntry.TokenUsage,
        availableModelKeys: Set<String>,
        cumulativeInputTokens: Int
    ) async -> (cost: Double, model: ModelIdentifier?) {
        // costUSD takes priority (ccusage auto mode)
        if let costUSD = costUSD {
            let model = rawModelId.map { ModelIdentifier(rawId: $0, availableModelKeys: availableModelKeys) }
            return (costUSD, model)
        }
        // Calculate from tokens if model available
        if let rawModelId = rawModelId {
            let identifier = ModelIdentifier(rawId: rawModelId, availableModelKeys: availableModelKeys)
            let tiered = await pricingService.tieredPricing(for: identifier.pricingKey)

            // Extract token counts
            let inputTokens = usage.inputTokens ?? 0
            let outputTokens = usage.outputTokens ?? 0
            let cacheCreationTokens = usage.cacheCreationInputTokens ?? 0
            let cacheReadTokens = usage.cacheReadInputTokens ?? 0

            // Calculate cost with tiered pricing
            var cost = 0.0

            // Output tokens use base rate always (no tiering)
            cost += Double(outputTokens) * tiered.base.outputCostPerToken

            // Input tokens: split if threshold exists
            if let threshold = tiered.inputTokenThreshold,
               let aboveRate = tiered.inputCostPerTokenAboveThreshold {
                // Calculate below and above threshold portions
                let belowThreshold = max(0, min(inputTokens, threshold - cumulativeInputTokens))
                let aboveThreshold = inputTokens - belowThreshold
                cost += Double(belowThreshold) * tiered.base.inputCostPerToken
                cost += Double(aboveThreshold) * aboveRate
            } else {
                // No tiering: use base rate
                cost += Double(inputTokens) * tiered.base.inputCostPerToken
            }

            // Cache creation tokens: split if threshold exists
            if let threshold = tiered.inputTokenThreshold,
               let aboveRate = tiered.cacheCreationCostPerTokenAboveThreshold {
                let belowThreshold = max(0, min(cacheCreationTokens, threshold - (cumulativeInputTokens + inputTokens)))
                let aboveThreshold = cacheCreationTokens - belowThreshold
                cost += Double(belowThreshold) * tiered.base.cacheCreationCostPerToken
                cost += Double(aboveThreshold) * aboveRate
            } else {
                cost += Double(cacheCreationTokens) * tiered.base.cacheCreationCostPerToken
            }

            // Cache read tokens: split if threshold exists
            if let threshold = tiered.inputTokenThreshold,
               let aboveRate = tiered.cacheReadCostPerTokenAboveThreshold {
                let belowThreshold = max(0, min(cacheReadTokens, threshold - (cumulativeInputTokens + inputTokens + cacheCreationTokens)))
                let aboveThreshold = cacheReadTokens - belowThreshold
                cost += Double(belowThreshold) * tiered.base.cacheReadCostPerToken
                cost += Double(aboveThreshold) * aboveRate
            } else {
                cost += Double(cacheReadTokens) * tiered.base.cacheReadCostPerToken
            }

            return (cost, identifier)
        }
        // No model, no costUSD = 0 cost
        return (0, nil)
    }

    // MARK: - Public Methods

    func findLatestSession() -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: claudeProjectsPath, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return nil }
        var latest: (URL, Date)?
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "jsonl",
                  !url.pathComponents.contains("subagents"),
                  let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modDate = values.contentModificationDate else { continue }

            if let current = latest {
                if modDate > current.1 {
                    latest = (url, modDate)
                }
            } else {
                latest = (url, modDate)
            }
        }
        return latest?.0
    }
    
    func parseSession(at url: URL, availableModelKeys: Set<String> = []) async throws -> SessionData {
        let lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: .newlines)
        var sessionId = url.deletingPathExtension().lastPathComponent
        var accumulator = TokenAccumulator()

        // Process main session file
        for line in lines where !line.isEmpty {
            guard let data = line.data(using: .utf8) else {
                logger.warning("Failed to convert line to UTF-8 data in \(url.lastPathComponent)")
                continue
            }

            guard let entry = try? decoder.decode(JSONLEntry.self, from: data) else {
                logger.debug("Skipping malformed JSONL line in \(url.lastPathComponent)")
                continue
            }

            if let sid = entry.sessionId { sessionId = sid }

            if let usage = accumulator.shouldProcess(entry) {
                let cumInput = accumulator.cumulativeInput(for: entry.rawModelId)
                let (cost, model) = await costForEntry(
                    costUSD: entry.costUSD,
                    rawModelId: entry.rawModelId,
                    usage: usage,
                    availableModelKeys: availableModelKeys,
                    cumulativeInputTokens: cumInput
                )
                accumulator.accumulate(usage: usage, rawModelId: entry.rawModelId, entryCost: cost, entryModel: model)
            }
        }

        // Process subagent JSONL files
        let sessionDir = url.deletingPathExtension()
        let subagentsDir = sessionDir.appendingPathComponent("subagents")

        if FileManager.default.fileExists(atPath: subagentsDir.path),
           let subagentFiles = try? FileManager.default.contentsOfDirectory(
               at: subagentsDir,
               includingPropertiesForKeys: nil,
               options: [.skipsHiddenFiles]
           ) {
            for subagentURL in subagentFiles where subagentURL.pathExtension == "jsonl" {
                guard let content = try? String(contentsOf: subagentURL, encoding: .utf8) else { continue }

                for line in content.components(separatedBy: .newlines) where !line.isEmpty {
                    guard let data = line.data(using: .utf8),
                          let entry = try? decoder.decode(JSONLEntry.self, from: data) else { continue }

                    if let usage = accumulator.shouldProcess(entry) {
                        let cumInput = accumulator.cumulativeInput(for: entry.rawModelId)
                        let (cost, model) = await costForEntry(
                            costUSD: entry.costUSD,
                            rawModelId: entry.rawModelId,
                            usage: usage,
                            availableModelKeys: availableModelKeys,
                            cumulativeInputTokens: cumInput
                        )
                        accumulator.accumulate(usage: usage, rawModelId: entry.rawModelId, entryCost: cost, entryModel: model)
                    }
                }
            }
        }

        return SessionData(sessionId: sessionId, tokens: accumulator.buildTokenStats(), models: accumulator.models)
    }

    func parseAggregate(since periodStart: Date, availableModelKeys: Set<String> = []) async -> SessionData {
        var accumulator = TokenAccumulator()

        guard let enumerator = FileManager.default.enumerator(
            at: claudeProjectsPath,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return SessionData(sessionId: nil, tokens: .zero, models: [])
        }

        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "jsonl" else { continue }

            // Skip files not modified since period start
            if let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
               let modDate = values.contentModificationDate,
               modDate < periodStart {
                continue
            }

            guard let content = try? String(contentsOf: url, encoding: .utf8) else { continue }

            for line in content.components(separatedBy: .newlines) where !line.isEmpty {
                guard let data = line.data(using: .utf8),
                      let entry = try? decoder.decode(JSONLEntry.self, from: data) else { continue }

                // Only include entries with timestamp >= periodStart
                guard let timestamp = entry.timestamp, timestamp >= periodStart else { continue }

                if let usage = accumulator.shouldProcess(entry) {
                    let cumInput = accumulator.cumulativeInput(for: entry.rawModelId)
                    let (cost, model) = await costForEntry(
                        costUSD: entry.costUSD,
                        rawModelId: entry.rawModelId,
                        usage: usage,
                        availableModelKeys: availableModelKeys,
                        cumulativeInputTokens: cumInput
                    )
                    accumulator.accumulate(usage: usage, rawModelId: entry.rawModelId, entryCost: cost, entryModel: model)
                }
            }
        }

        return SessionData(sessionId: nil, tokens: accumulator.buildTokenStats(), models: accumulator.models)
    }

    func parseForPeriod(_ period: StatisticsPeriod, sessionURL: URL? = nil, availableModelKeys: Set<String> = []) async throws -> SessionData? {
        switch period {
        case .session:
            guard let url = sessionURL ?? findLatestSession() else { return nil }
            return try await parseSession(at: url, availableModelKeys: availableModelKeys)
        case .today, .thisWeek, .thisMonth:
            guard let start = period.periodStart() else { return nil }
            return await parseAggregate(since: start, availableModelKeys: availableModelKeys)
        }
    }
    
    func getContextWindowForFile(at url: URL, availableModelKeys: Set<String> = []) throws -> ContextWindow {
        for line in try String(contentsOf: url, encoding: .utf8).components(separatedBy: .newlines).reversed() {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let entry = try? decoder.decode(JSONLEntry.self, from: data),
                  let usage = entry.message?.usage else { continue }

            let activeModel: ModelIdentifier? = entry.rawModelId.map {
                ModelIdentifier(rawId: $0, availableModelKeys: availableModelKeys)
            }
            let finalModel = activeModel?.family != .unknown ? activeModel : nil
            return ContextWindow(currentTokens: usage.totalInputTokens, activeModel: finalModel)
        }

        return ContextWindow(currentTokens: 0, activeModel: nil)
    }

    func getCurrentContextWindow(availableModelKeys: Set<String> = []) throws -> ContextWindow {
        guard let url = findLatestSession() else {
            return ContextWindow(currentTokens: 0, activeModel: nil)
        }
        return try getContextWindowForFile(at: url, availableModelKeys: availableModelKeys)
    }

    func findActiveAgents(for sessionURL: URL, threshold: TimeInterval = 30) -> [(url: URL, agentId: String, lastModified: Date)] {
        let sessionDir = sessionURL.deletingPathExtension()
        let subagentsDir = sessionDir.appendingPathComponent("subagents")

        guard FileManager.default.fileExists(atPath: subagentsDir.path) else { return [] }

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: subagentsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let now = Date()
        var agents: [(url: URL, agentId: String, lastModified: Date)] = []

        for url in contents {
            guard url.pathExtension == "jsonl",
                  let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modDate = values.contentModificationDate,
                  now.timeIntervalSince(modDate) <= threshold else { continue }

            let agentId = url.deletingPathExtension().lastPathComponent
            agents.append((url: url, agentId: agentId, lastModified: modDate))
        }

        return agents
    }

    func getContextWindowState(availableModelKeys: Set<String> = [], agentThreshold: TimeInterval = 30) throws -> ContextWindowState? {
        guard let sessionURL = findLatestSession() else { return nil }
        return try getContextWindowState(for: sessionURL, availableModelKeys: availableModelKeys, agentThreshold: agentThreshold)
    }

    func getContextWindowState(for sessionURL: URL, availableModelKeys: Set<String> = [], agentThreshold: TimeInterval = 30) throws -> ContextWindowState {
        let mainContext = try getContextWindowForFile(at: sessionURL, availableModelKeys: availableModelKeys)
        let activeAgentFiles = findActiveAgents(for: sessionURL, threshold: agentThreshold)

        var agentContexts: [AgentContext] = []
        for agent in activeAgentFiles {
            guard let ctx = try? getContextWindowForFile(at: agent.url, availableModelKeys: availableModelKeys),
                  ctx.currentTokens > 0 else { continue }
            agentContexts.append(AgentContext(
                agentId: agent.agentId,
                contextWindow: ctx,
                lastModified: agent.lastModified
            ))
        }

        agentContexts.sort { $0.lastModified > $1.lastModified }
        return ContextWindowState(main: mainContext, activeAgents: agentContexts)
    }

    func findActiveSessions(threshold: TimeInterval) -> [ActiveSession] {
        guard let enumerator = FileManager.default.enumerator(
            at: claudeProjectsPath,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let cutoff = Date().addingTimeInterval(-threshold)
        // Group by project directory, keeping only the newest session per project
        var newestByProject: [String: (url: URL, date: Date)] = [:]

        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "jsonl",
                  !url.pathComponents.contains("subagents"),
                  let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modDate = values.contentModificationDate,
                  modDate >= cutoff else { continue }

            // Project directory is the parent of the JSONL file
            let projectDir = url.deletingLastPathComponent().lastPathComponent

            if let existing = newestByProject[projectDir] {
                if modDate > existing.date {
                    newestByProject[projectDir] = (url, modDate)
                }
            } else {
                newestByProject[projectDir] = (url, modDate)
            }
        }

        return newestByProject.map { (projectDir, entry) in
            ActiveSession(
                sessionURL: entry.url,
                projectDirectory: projectDir,
                projectName: ActiveSession.extractProjectName(from: projectDir),
                lastModified: entry.date
            )
        }
        .sorted { $0.lastModified > $1.lastModified }
    }

    /// Returns the single most recently modified session across all projects, ignoring any activity threshold.
    func findMostRecentSession() -> ActiveSession? {
        guard let enumerator = FileManager.default.enumerator(
            at: claudeProjectsPath,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var newest: (url: URL, date: Date)?

        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "jsonl",
                  !url.pathComponents.contains("subagents"),
                  let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modDate = values.contentModificationDate else { continue }

            if newest == nil || modDate > newest!.date {
                newest = (url, modDate)
            }
        }

        guard let result = newest else { return nil }
        let projectDir = result.url.deletingLastPathComponent().lastPathComponent
        return ActiveSession(
            sessionURL: result.url,
            projectDirectory: projectDir,
            projectName: ActiveSession.extractProjectName(from: projectDir),
            lastModified: result.date
        )
    }
}
