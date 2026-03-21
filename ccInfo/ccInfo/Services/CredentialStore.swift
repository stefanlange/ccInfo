import Foundation
import Security
import OSLog

/// Thread-safe file-based credential storage for Claude credentials.
/// Credentials are stored at ~/Library/Application Support/ccInfo/credentials.json
/// with 0600 permissions. On first access, migrates any existing Keychain entry
/// and then removes it so the macOS password prompt never reappears after updates.
@MainActor
final class CredentialStore: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.ccinfo.app", category: "CredentialStore")
    private var _hasCredentials: Bool?
    private var _hasMigrated = false

    // MARK: - Storage path

    private var credentialsFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("ccInfo/credentials.json")
    }

    private func ensureDirectoryExists() {
        let dir = credentialsFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    // MARK: - Public API

    func saveCredentials(_ credentials: ClaudeCredentials) -> Bool {
        guard let data = try? JSONEncoder().encode(credentials) else {
            logger.warning("Failed to encode credentials")
            return false
        }
        ensureDirectoryExists()
        let url = credentialsFileURL
        do {
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            logger.warning("Failed to write credentials: \(error.localizedDescription)")
            _hasCredentials = nil
            return false
        }
        _hasCredentials = true
        return true
    }

    func getCredentials() -> ClaudeCredentials? {
        if let data = try? Data(contentsOf: credentialsFileURL),
           let credentials = try? JSONDecoder().decode(ClaudeCredentials.self, from: data) {
            return credentials
        }
        // File not found or unreadable — attempt one-time Keychain migration
        if !_hasMigrated {
            _hasMigrated = true
            return migrateFromKeychain()
        }
        return nil
    }

    @discardableResult
    func deleteCredentials() -> Bool {
        _hasCredentials = false
        let url = credentialsFileURL
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as NSError where error.code == NSFileNoSuchFileError {
            return true
        } catch {
            logger.warning("Failed to delete credentials: \(error.localizedDescription)")
            return false
        }
        return true
    }

    var hasCredentials: Bool {
        if let cached = _hasCredentials { return cached }
        let result = getCredentials() != nil
        _hasCredentials = result
        return result
    }

    // MARK: - Keychain migration (runs once, then never again)

    private func migrateFromKeychain() -> ClaudeCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.ccinfo.app",
            kSecAttrAccount as String: "claude-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data,
              let credentials = try? JSONDecoder().decode(ClaudeCredentials.self, from: data) else {
            return nil
        }

        logger.info("Migrating credentials from Keychain to file storage")

        // Persist to file
        guard saveCredentials(credentials) else {
            logger.warning("Migration failed: could not write credentials to file")
            return credentials // return the found creds even if file write failed
        }

        // Delete Keychain entry so the password dialog never appears again
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.ccinfo.app",
            kSecAttrAccount as String: "claude-credentials"
        ]
        let deleteStatus = SecItemDelete(deleteQuery as CFDictionary)
        if deleteStatus != errSecSuccess {
            logger.warning("Migration: failed to delete Keychain entry (status \(deleteStatus)) — will retry next launch")
        } else {
            logger.info("Migration complete: Keychain entry removed")
        }

        return credentials
    }
}
