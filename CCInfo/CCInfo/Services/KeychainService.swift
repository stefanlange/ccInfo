import Foundation
import Security
import OSLog

/// Thread-safe Keychain service for storing Claude credentials
@MainActor
final class KeychainService: @unchecked Sendable {
    private let service = "com.ccinfo.app"
    private let account = "claude-credentials"
    private let logger = Logger(subsystem: "com.ccinfo.app", category: "Keychain")
    private var _hasCredentials: Bool?

    func saveCredentials(_ credentials: ClaudeCredentials) -> Bool {
        guard let data = try? JSONEncoder().encode(credentials) else {
            logger.error("Failed to encode credentials")
            return false
        }
        deleteCredentials()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("Failed to save credentials: \(status)")
        }
        let success = status == errSecSuccess
        _hasCredentials = success ? true : nil
        return success
    }

    func getCredentials() -> ClaudeCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(ClaudeCredentials.self, from: data)
    }

    @discardableResult
    func deleteCredentials() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        _hasCredentials = false
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }

    var hasCredentials: Bool {
        if let cached = _hasCredentials { return cached }
        let result = getCredentials() != nil
        _hasCredentials = result
        return result
    }
}
