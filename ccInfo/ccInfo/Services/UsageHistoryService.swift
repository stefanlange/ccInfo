import Foundation
import OSLog

/// Service for collecting, persisting, and managing the 5-hour usage history timeline.
@MainActor
final class UsageHistoryService {
    private let logger = Logger(subsystem: "com.ccinfo.app", category: "UsageHistoryService")

    /// In-memory storage of data points
    private var dataPoints: [UsageDataPoint] = []

    /// Read-only access to the current history (for Phase 12 chart binding)
    var history: [UsageDataPoint] { dataPoints }

    /// Gap detection threshold: 3x the 30s poll interval = 90 seconds
    private let gapThreshold: TimeInterval = 90

    /// Window duration: 5 hours
    private let windowDuration: TimeInterval = 5 * 60 * 60

    /// Periodic save interval: save every 30 data points (~15 minutes at 30s intervals)
    private let saveInterval = 30

    /// Counter for periodic saves
    private var recordCount = 0

    /// Suppress gap detection for the first record after loading from disk,
    /// so the chart connects smoothly to persisted history after an app restart.
    private var suppressNextGap = false

    /// File URL for persistent storage
    private var fileURL: URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            logger.error("Application Support directory not found")
            return nil
        }
        let ccInfoDir = appSupport.appendingPathComponent("ccInfo")
        // Migrate from old "CCInfo" directory if it exists
        let oldDir = appSupport.appendingPathComponent("CCInfo")
        if FileManager.default.fileExists(atPath: oldDir.path) && !FileManager.default.fileExists(atPath: ccInfoDir.path) {
            try? FileManager.default.moveItem(at: oldDir, to: ccInfoDir)
        }
        return ccInfoDir.appendingPathComponent("usageHistory.json")
    }

    // MARK: - Public Methods

    /// Record a new usage data point
    func record(usagePercent: Int) {
        let clamped = max(0, min(100, usagePercent))
        let now = Date()

        // Insert a separate gap marker so the actual data point draws normally.
        // Skip gap detection right after loading from disk (app restart).
        if suppressNextGap {
            suppressNextGap = false
        } else if detectGap(at: now), let last = dataPoints.last {
            let gapTime = last.timestamp.addingTimeInterval(1)
            dataPoints.append(UsageDataPoint(timestamp: gapTime, usage: last.usage, isGap: true))
        }

        let dataPoint = UsageDataPoint(timestamp: now, usage: clamped)
        dataPoints.append(dataPoint)

        pruneOldPoints()

        recordCount += 1
        if recordCount >= saveInterval {
            saveToDisk()
            recordCount = 0
        }
    }

    /// Load persisted data from disk and filter to current 5h window
    func loadFromDisk() {
        guard let url = fileURL else { return }
        do {
            guard FileManager.default.fileExists(atPath: url.path) else {
                logger.info("No persisted history found at startup")
                return
            }

            let data = try Data(contentsOf: url)
            let loaded = try JSONDecoder().decode([UsageDataPoint].self, from: data)

            let now = Date()
            let fiveHoursAgo = now.addingTimeInterval(-windowDuration)
            dataPoints = loaded.filter { $0.timestamp > fiveHoursAgo }
            if !dataPoints.isEmpty {
                suppressNextGap = true
            }

            logger.info("Loaded \(loaded.count) data points, \(self.dataPoints.count) within 5h window")
        } catch {
            logger.error("Failed to load history from disk: \(error.localizedDescription)")
        }
    }

    /// Persist current data points to disk
    func saveToDisk() {
        guard let url = fileURL else { return }
        do {
            let dir = url.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(dataPoints)
            try data.write(to: url, options: .atomic)

            logger.info("Saved \(self.dataPoints.count) data points to disk")
        } catch {
            logger.error("Failed to save history to disk: \(error.localizedDescription)")
        }
    }

    /// Clear all data points and overwrite the file (called on window reset)
    func handleWindowReset() {
        dataPoints.removeAll()
        recordCount = 0
        saveToDisk()
        logger.info("History cleared due to window reset")
    }

    // MARK: - Private Helpers

    /// Detect if there's a gap since the last data point
    private func detectGap(at timestamp: Date) -> Bool {
        guard let lastPoint = dataPoints.last else { return false }
        let timeSinceLastPoint = timestamp.timeIntervalSince(lastPoint.timestamp)
        return timeSinceLastPoint > gapThreshold
    }

    /// Remove data points older than 5 hours
    private func pruneOldPoints() {
        let now = Date()
        let fiveHoursAgo = now.addingTimeInterval(-windowDuration)
        let originalCount = dataPoints.count
        dataPoints.removeAll { $0.timestamp <= fiveHoursAgo }

        let prunedCount = originalCount - dataPoints.count
        if prunedCount > 0 {
            logger.debug("Pruned \(prunedCount) old data points")
        }
    }
}
