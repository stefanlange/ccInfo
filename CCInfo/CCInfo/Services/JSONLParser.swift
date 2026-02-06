import Foundation
import OSLog

final class JSONLParser {
    private let claudeProjectsPath: URL
    private let decoder: JSONDecoder
    private let logger = Logger(subsystem: "com.ccinfo.app", category: "JSONLParser")

    init() {
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
    
    func parseSession(at url: URL) throws -> SessionData {
        let lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: .newlines)
        var tokens = SessionData.TokenStats.zero
        var sessionId = url.deletingPathExtension().lastPathComponent
        var detectedModels: Set<ClaudeModel> = []

        for line in lines where !line.isEmpty {
            guard let data = line.data(using: .utf8) else {
                logger.warning("Failed to convert line to UTF-8 data in \(url.lastPathComponent)")
                continue
            }

            guard let entry = try? decoder.decode(JSONLEntry.self, from: data) else {
                // Log parsing failures for debugging (common with malformed JSONL)
                logger.debug("Skipping malformed JSONL line in \(url.lastPathComponent)")
                continue
            }

            if let sid = entry.sessionId { sessionId = sid }

            // Track all models used in this session
            let entryModel = entry.detectedModel
            if entryModel != .unknown {
                detectedModels.insert(entryModel)
            }

            if let u = entry.message?.usage {
                let input = u.inputTokens ?? 0
                let output = u.outputTokens ?? 0
                let cacheCreation = u.cacheCreationInputTokens ?? 0
                let cacheRead = u.cacheReadInputTokens ?? 0
                let pricing = entryModel.pricing
                let entryCost = Double(input) / 1_000_000 * pricing.input
                             + Double(output) / 1_000_000 * pricing.output
                             + Double(cacheCreation) / 1_000_000 * pricing.cacheWrite
                             + Double(cacheRead) / 1_000_000 * pricing.cacheRead
                tokens = tokens + SessionData.TokenStats(
                    input: input, output: output, cacheCreation: cacheCreation,
                    cacheRead: cacheRead, cost: entryCost)
            }
        }

        // If no models detected, add unknown
        if detectedModels.isEmpty {
            detectedModels.insert(.unknown)
        }

        return SessionData(sessionId: sessionId, tokens: tokens, models: detectedModels)
    }
    
    func getCurrentContextWindow() throws -> ContextWindow {
        guard let url = findLatestSession() else {
            return ContextWindow(currentTokens: 0, activeModel: nil)
        }

        for line in try String(contentsOf: url, encoding: .utf8).components(separatedBy: .newlines).reversed() {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let entry = try? decoder.decode(JSONLEntry.self, from: data),
                  let usage = entry.message?.usage else { continue }

            // Extract model from newest entry
            let activeModel = entry.detectedModel
            return ContextWindow(
                currentTokens: usage.totalInputTokens,
                activeModel: activeModel != .unknown ? activeModel : nil
            )
        }

        return ContextWindow(currentTokens: 0, activeModel: nil)
    }
}
