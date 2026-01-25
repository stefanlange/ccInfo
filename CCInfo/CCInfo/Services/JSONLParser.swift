import Foundation

final class JSONLParser {
    private let claudeProjectsPath: URL
    private let decoder: JSONDecoder
    
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
            if latest == nil || modDate > latest!.1 { latest = (url, modDate) }
        }
        return latest?.0
    }
    
    func parseSession(at url: URL) throws -> SessionData {
        let lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: .newlines)
        var tokens = SessionData.TokenStats.zero
        var sessionId = url.deletingPathExtension().lastPathComponent
        for line in lines where !line.isEmpty {
            guard let data = line.data(using: .utf8), let entry = try? decoder.decode(JSONLEntry.self, from: data) else { continue }
            if let sid = entry.sessionId { sessionId = sid }
            if entry.message?.role == "assistant", let u = entry.message?.usage {
                tokens = tokens + SessionData.TokenStats(input: u.inputTokens ?? 0, output: u.outputTokens ?? 0,
                    cacheCreation: u.cacheCreationInputTokens ?? 0, cacheRead: u.cacheReadInputTokens ?? 0)
            }
        }
        return SessionData(sessionId: sessionId, tokens: tokens)
    }
    
    func getCurrentContextWindow() throws -> ContextWindow {
        guard let url = findLatestSession() else { return ContextWindow(currentTokens: 0) }
        for line in try String(contentsOf: url, encoding: .utf8).components(separatedBy: .newlines).reversed() {
            guard !line.isEmpty, let data = line.data(using: .utf8),
                  let entry = try? decoder.decode(JSONLEntry.self, from: data),
                  let usage = entry.message?.usage else { continue }
            return ContextWindow(currentTokens: usage.totalInputTokens)
        }
        return ContextWindow(currentTokens: 0)
    }
}
