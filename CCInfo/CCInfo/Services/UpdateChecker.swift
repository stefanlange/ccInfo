import Foundation
import OSLog

struct AvailableUpdate {
    let version: String
    let url: URL
}

enum UpdateChecker {
    private static let logger = Logger(subsystem: "com.ccinfo.app", category: "UpdateChecker")

    static func checkForUpdate() async -> AvailableUpdate? {
        let urlString = "https://api.github.com/repos/stefanlange/ccInfo/releases/latest"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                logger.warning("GitHub API returned non-200 status")
                return nil
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let remoteVersion = release.tagName.trimmingCharacters(in: .init(charactersIn: "vV"))

            guard let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String else {
                return nil
            }

            if isNewer(remote: remoteVersion, thanLocal: currentVersion) {
                guard let htmlURL = URL(string: release.htmlURL) else { return nil }
                return AvailableUpdate(version: remoteVersion, url: htmlURL)
            }
            return nil
        } catch {
            logger.error("Update check failed: \(error.localizedDescription)")
            return nil
        }
    }

    private static func isNewer(remote: String, thanLocal local: String) -> Bool {
        let remoteComponents = remote.split(separator: ".").compactMap { Int($0) }
        let localComponents = local.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(remoteComponents.count, localComponents.count) {
            let r = i < remoteComponents.count ? remoteComponents[i] : 0
            let l = i < localComponents.count ? localComponents[i] : 0
            if r > l { return true }
            if r < l { return false }
        }
        return false
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}
