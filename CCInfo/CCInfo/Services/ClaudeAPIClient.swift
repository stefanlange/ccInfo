import Foundation
import OSLog

actor ClaudeAPIClient {
    private let baseURL = "https://claude.ai/api"
    private let keychainService: KeychainService
    private let logger = Logger(subsystem: "com.ccinfo.app", category: "API")

    enum APIError: Error, LocalizedError {
        case notAuthenticated
        case invalidURL
        case invalidResponse
        case httpError(Int)
        case sessionExpired

        var errorDescription: String? {
            switch self {
            case .notAuthenticated: String(localized: "Not authenticated")
            case .invalidURL: String(localized: "Invalid URL")
            case .invalidResponse: String(localized: "Invalid server response")
            case .httpError(let code): String(localized: "HTTP error: \(code)")
            case .sessionExpired: String(localized: "Session expired")
            }
        }
    }

    init(keychainService: KeychainService) {
        self.keychainService = keychainService
    }

    func fetchUsage() async throws -> UsageData {
        guard let creds = await keychainService.getCredentials() else {
            throw APIError.notAuthenticated
        }

        guard let url = URL(string: "\(baseURL)/organizations/\(creds.organizationId)/usage") else {
            logger.error("Failed to construct usage URL for org: \(creds.organizationId.prefix(8))...")
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("sessionKey=\(creds.sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("web_claude_ai", forHTTPHeaderField: "anthropic-client-platform")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if http.statusCode == 401 {
            await keychainService.deleteCredentials()
            throw APIError.sessionExpired
        }

        guard http.statusCode == 200 else {
            logger.warning("API returned status code: \(http.statusCode)")
            throw APIError.httpError(http.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return UsageData(from: try decoder.decode(UsageResponse.self, from: data))
    }
}

struct ClaudeCredentials: Codable, Sendable {
    let sessionKey: String
    let organizationId: String
    let createdAt: Date
}
