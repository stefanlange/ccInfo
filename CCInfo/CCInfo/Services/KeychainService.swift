import Foundation
import Security
import OSLog

/// Thread-safe Keychain service for storing Claude credentials
@MainActor
final class KeychainService {
    private let service = "com.ccinfo.app"
    private let account = "claude-credentials"
    private let logger = Logger(subsystem: "com.ccinfo.app", category: "Keychain")

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
        return status == errSecSuccess
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
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }

    var hasCredentials: Bool { getCredentials() != nil }
}
