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
    
    // MARK: - Private Types

    private struct TokenCounts {
        var input = 0
        var output = 0
        var cacheCreation = 0
        var cacheRead = 0
    }

    // MARK: - Private Methods

    private func calculateCost(
        tokensByModel: [String: TokenCounts],
        availableModelKeys: Set<String>
    ) async -> (cost: Double, models: Set<ModelIdentifier>) {
        var totalCost = 0.0
        var models: Set<ModelIdentifier> = []

        for (rawModelId, counts) in tokensByModel {
            let identifier = ModelIdentifier(rawId: rawModelId, availableModelKeys: availableModelKeys)
            models.insert(identifier)
            let pricing = await pricingService.pricing(for: identifier.pricingKey)

            let modelCost = Double(counts.input) * pricing.inputCostPerToken
                          + Double(counts.output) * pricing.outputCostPerToken
                          + Double(counts.cacheCreation) * pricing.cacheCreationCostPerToken
                          + Double(counts.cacheRead) * pricing.cacheReadCostPerToken
            totalCost += modelCost
        }

        return (totalCost, models)
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
        var tokensByModel: [String: TokenCounts] = [:]
        var totalInput = 0
        var totalOutput = 0
        var totalCacheCreation = 0
        var totalCacheRead = 0

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

            // Skip entries without usage or valid model ID
            guard let usage = entry.message?.usage,
                  let rawModelId = entry.rawModelId,
                  rawModelId != "<synthetic>" else { continue }

            // Accumulate tokens per model
            var counts = tokensByModel[rawModelId, default: TokenCounts()]
            counts.input += usage.inputTokens ?? 0
            counts.output += usage.outputTokens ?? 0
            counts.cacheCreation += usage.cacheCreationInputTokens ?? 0
            counts.cacheRead += usage.cacheReadInputTokens ?? 0
            tokensByModel[rawModelId] = counts

            // Also accumulate totals for TokenStats
            totalInput += usage.inputTokens ?? 0
            totalOutput += usage.outputTokens ?? 0
            totalCacheCreation += usage.cacheCreationInputTokens ?? 0
            totalCacheRead += usage.cacheReadInputTokens ?? 0
        }

        // Calculate cost and models
        let (cost, models) = tokensByModel.isEmpty
            ? (0.0, Set([.unknown]))
            : await calculateCost(tokensByModel: tokensByModel, availableModelKeys: availableModelKeys)

        let tokens = SessionData.TokenStats(
            input: totalInput,
            output: totalOutput,
            cacheCreation: totalCacheCreation,
            cacheRead: totalCacheRead,
            cost: cost
        )

        return SessionData(sessionId: sessionId, tokens: tokens, models: models)
    }

    func parseAggregate(since periodStart: Date, availableModelKeys: Set<String> = []) async -> SessionData {
        var tokensByModel: [String: TokenCounts] = [:]
        var totalInput = 0
        var totalOutput = 0
        var totalCacheCreation = 0
        var totalCacheRead = 0

        guard let enumerator = FileManager.default.enumerator(
            at: claudeProjectsPath,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return SessionData(sessionId: nil, tokens: .zero, models: [.unknown])
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

                // Skip entries without usage or valid model ID
                guard let usage = entry.message?.usage,
                      let rawModelId = entry.rawModelId,
                      rawModelId != "<synthetic>" else { continue }

                // Accumulate tokens per model
                var counts = tokensByModel[rawModelId, default: TokenCounts()]
                counts.input += usage.inputTokens ?? 0
                counts.output += usage.outputTokens ?? 0
                counts.cacheCreation += usage.cacheCreationInputTokens ?? 0
                counts.cacheRead += usage.cacheReadInputTokens ?? 0
                tokensByModel[rawModelId] = counts

                // Also accumulate totals for TokenStats
                totalInput += usage.inputTokens ?? 0
                totalOutput += usage.outputTokens ?? 0
                totalCacheCreation += usage.cacheCreationInputTokens ?? 0
                totalCacheRead += usage.cacheReadInputTokens ?? 0
            }
        }

        // Calculate cost and models
        let (cost, models) = tokensByModel.isEmpty
            ? (0.0, Set([.unknown]))
            : await calculateCost(tokensByModel: tokensByModel, availableModelKeys: availableModelKeys)

        let tokens = SessionData.TokenStats(
            input: totalInput,
            output: totalOutput,
            cacheCreation: totalCacheCreation,
            cacheRead: totalCacheRead,
            cost: cost
        )

        return SessionData(sessionId: nil, tokens: tokens, models: models)
    }

    func parseForPeriod(_ period: StatisticsPeriod, availableModelKeys: Set<String> = []) async throws -> SessionData? {
        switch period {
        case .session:
            guard let url = findLatestSession() else { return nil }
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
}
