import Foundation
import OSLog

actor ClaudeAPIClient {
    private static let baseURL = "https://claude.ai/api"
    private let credentialStore: CredentialStore
    private let logger = Logger(subsystem: "com.ccinfo.app", category: "API")

    enum APIError: Error, LocalizedError {
        case notAuthenticated
        case invalidURL
        case invalidResponse
        case httpError(Int)
        case sessionExpired
        case incompleteUsageData(field: String)

        var errorDescription: String? {
            switch self {
            case .notAuthenticated: String(localized: "Not authenticated")
            case .invalidURL: String(localized: "Invalid URL")
            case .invalidResponse: String(localized: "Invalid server response")
            case .httpError(let code): String(localized: "HTTP error: \(code)")
            case .sessionExpired: String(localized: "Session expired")
            case .incompleteUsageData(let field): String(localized: "Usage data incomplete (missing \(field))")
            }
        }
    }

    init(credentialStore: CredentialStore) {
        self.credentialStore = credentialStore
    }

    func fetchUsage() async throws -> UsageData {
        guard let creds = await credentialStore.getCredentials() else {
            throw APIError.notAuthenticated
        }

        guard let encodedOrgId = creds.organizationId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw APIError.invalidURL
        }

        guard let url = URL(string: "\(Self.baseURL)/organizations/\(encodedOrgId)/usage") else {
            logger.error("Failed to construct usage URL for organization")
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

        guard http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "<non-UTF8 body, \(data.count) bytes>"
            let truncatedBody = body.count > 512 ? String(body.prefix(512)) + "…" : body
            logger.warning("\(url.absoluteString, privacy: .private) returned \(http.statusCode): \(truncatedBody, privacy: .private)")

            if http.statusCode == 401 || (http.statusCode == 403 && body.contains("account_session_invalid")) {
                await credentialStore.deleteCredentials()
                throw APIError.sessionExpired
            }

            throw APIError.httpError(http.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let usageResponse = try decoder.decode(UsageResponse.self, from: data)

        // A successfully-decoded response with a missing mandatory window is a
        // transient backend anomaly (observed in production), not a legitimate 0%
        // reading. Treat it as a fetch failure so the caller skips this poll
        // instead of UsageData silently falling back to `utilization = 0`.
        guard usageResponse.fiveHour != nil else {
            logger.warning("Usage response missing five_hour window; skipping poll")
            throw APIError.incompleteUsageData(field: "five_hour")
        }
        guard usageResponse.sevenDay != nil else {
            logger.warning("Usage response missing seven_day window; skipping poll")
            throw APIError.incompleteUsageData(field: "seven_day")
        }
        return UsageData(from: usageResponse)
    }

    /// Fetch organization name for display purposes
    static func fetchOrganizationName(organizationId: String, sessionKey: String) async throws -> String {
        guard let encodedOrgId = organizationId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            throw APIError.invalidURL
        }

        guard let url = URL(string: "\(Self.baseURL)/organizations/\(encodedOrgId)/dust/org_shortname") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("web_claude_ai", forHTTPHeaderField: "anthropic-client-platform")
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard http.statusCode == 200 else {
            throw APIError.httpError(http.statusCode)
        }

        struct OrgNameResponse: Codable {
            let shortname: String
        }

        let orgResponse = try JSONDecoder().decode(OrgNameResponse.self, from: data)
        return orgResponse.shortname
    }
}

struct ClaudeCredentials: Codable, Sendable {
    let sessionKey: String
    let organizationId: String
    let organizationName: String?
    let createdAt: Date
}
