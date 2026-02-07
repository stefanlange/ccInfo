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
    
    func findLatestSession() -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: claudeProjectsPath, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return nil }
        var latest: (URL, Date)?
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "jsonl",
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
    
    func parseSession(at url: URL, availableModelKeys: Set<String> = []) throws -> SessionData {
        let lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: .newlines)
        var tokens = SessionData.TokenStats.zero
        var sessionId = url.deletingPathExtension().lastPathComponent
        var rawModelIds: Set<String> = []

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

            if let modelId = entry.rawModelId, modelId != "<synthetic>" {
                rawModelIds.insert(modelId)
            }

            if let entryTokens = accumulateTokens(from: entry) {
                tokens = tokens + entryTokens
            }
        }

        let models: Set<ModelIdentifier> = rawModelIds.isEmpty
            ? [.unknown]
            : Set(rawModelIds.map { ModelIdentifier(rawId: $0, availableModelKeys: availableModelKeys) })

        return SessionData(sessionId: sessionId, tokens: tokens, models: models)
    }

    func parseAggregate(since periodStart: Date, availableModelKeys: Set<String> = []) -> SessionData {
        var tokens = SessionData.TokenStats.zero
        var rawModelIds: Set<String> = []

        guard let enumerator = FileManager.default.enumerator(
            at: claudeProjectsPath,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return SessionData(sessionId: nil, tokens: tokens, models: [.unknown])
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

                if let modelId = entry.rawModelId, modelId != "<synthetic>" {
                    rawModelIds.insert(modelId)
                }

                if let entryTokens = accumulateTokens(from: entry) {
                    tokens = tokens + entryTokens
                }
            }
        }

        let models: Set<ModelIdentifier> = rawModelIds.isEmpty
            ? [.unknown]
            : Set(rawModelIds.map { ModelIdentifier(rawId: $0, availableModelKeys: availableModelKeys) })

        return SessionData(sessionId: nil, tokens: tokens, models: models)
    }

    func parseForPeriod(_ period: StatisticsPeriod, availableModelKeys: Set<String> = []) throws -> SessionData? {
        switch period {
        case .session:
            guard let url = findLatestSession() else { return nil }
            return try parseSession(at: url, availableModelKeys: availableModelKeys)
        case .today, .thisWeek, .thisMonth:
            guard let start = period.periodStart() else { return nil }
            return parseAggregate(since: start, availableModelKeys: availableModelKeys)
        }
    }
    
    func getCurrentContextWindow(availableModelKeys: Set<String> = []) throws -> ContextWindow {
        guard let url = findLatestSession() else {
            return ContextWindow(currentTokens: 0, activeModel: nil)
        }

        for line in try String(contentsOf: url, encoding: .utf8).components(separatedBy: .newlines).reversed() {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let entry = try? decoder.decode(JSONLEntry.self, from: data),
                  let usage = entry.message?.usage else { continue }

            let activeModel: ModelIdentifier? = entry.rawModelId.map {
                ModelIdentifier(rawId: $0, availableModelKeys: availableModelKeys)
            }
            // Only return non-unknown models
            let finalModel = activeModel?.family != .unknown ? activeModel : nil
            return ContextWindow(currentTokens: usage.totalInputTokens, activeModel: finalModel)
        }

        return ContextWindow(currentTokens: 0, activeModel: nil)
    }
}
