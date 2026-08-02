import Foundation
import OSLog

enum BurnRateCalculator {
    private static let logger = Logger(subsystem: "com.ccinfo.app", category: "BurnRateCalculator")

    /// Maximum plausible usage-percent change per second between two
    /// consecutive polls. Expressed as a rate (not a fixed point-count) so it
    /// scales correctly regardless of the user-configured poll interval
    /// (default 30s, see MenuBarConfiguration.Defaults.refreshInterval).
    /// 20 points per default 30s poll (~0.667 %/s) is comfortably above any
    /// realistic single-poll token-burn burst, yet well below a one-poll
    /// glitch spike (observed: ~35 points in ~30s from a phantom 0% reading,
    /// see UsageHistoryService.record).
    private static let maxPlausibleRatePerSecond: Double = 20.0 / 30.0

    struct Prediction {
        let hitsLimitAt: Date
        let minutesUntilLimit: Int

        var formattedTimeUntilLimit: String {
            if minutesUntilLimit >= 60 {
                let h = minutesUntilLimit / 60
                let m = minutesUntilLimit % 60
                return m > 0 ? String(format: "~%dh %02dmin", h, m) : "~\(h)h"
            }
            return "~\(minutesUntilLimit)min"
        }
    }

    /// Analyze recent usage history to predict if 100% will be reached before resetsAt.
    /// Returns nil if there is no risk (usage is flat/declining, too few data points, or
    /// current utilization is too low to warrant a warning).
    static func predict(
        history: [UsageDataPoint],
        currentUtilization: Double,
        resetsAt: Date?
    ) -> Prediction? {
        let now = Date()

        // Guard: need resetsAt in the future
        guard let resetsAt, resetsAt > now else { return nil }

        // Guard: skip trivial usage levels
        guard currentUtilization >= 20 else { return nil }

        // Collect non-gap points from the last 15 minutes
        let cutoff = now.addingTimeInterval(-15 * 60)
        let recentPoints = history.filter { !$0.isGap && $0.timestamp >= cutoff }

        // Drop individual points whose jump from the last accepted point exceeds
        // what's physically plausible in the elapsed time — a single spurious
        // reading must not dominate the regression's slope.
        let plausiblePoints = filterOutliers(recentPoints)

        // Guard: need at least 3 data points
        guard plausiblePoints.count >= 3 else { return nil }

        // Linear regression: find slope in usage-percent per second
        // Use the earliest point as the reference time to avoid floating-point precision issues
        let referenceTime = plausiblePoints.first!.timestamp
        let pairs: [(x: Double, y: Double)] = plausiblePoints.map { point in
            (x: point.timestamp.timeIntervalSince(referenceTime),
             y: Double(point.usage))
        }

        let n = Double(pairs.count)
        let sumX = pairs.reduce(0.0) { $0 + $1.x }
        let sumY = pairs.reduce(0.0) { $0 + $1.y }
        let sumXY = pairs.reduce(0.0) { $0 + $1.x * $1.y }
        let sumXX = pairs.reduce(0.0) { $0 + $1.x * $1.x }

        let denominator = n * sumXX - sumX * sumX
        guard abs(denominator) > 0 else { return nil }

        let slope = (n * sumXY - sumX * sumY) / denominator // usage-percent per second

        // Guard: usage must be increasing
        guard slope > 0 else { return nil }

        // Project time until 100%
        let remaining = 100.0 - currentUtilization
        let secondsToLimit = remaining / slope
        guard secondsToLimit > 0 else { return nil }

        let hitsLimitAt = now.addingTimeInterval(secondsToLimit)

        // Only warn if projected exhaustion is BEFORE the window resets
        guard hitsLimitAt < resetsAt else { return nil }

        let minutesUntilLimit = max(1, Int(secondsToLimit / 60))
        return Prediction(hitsLimitAt: hitsLimitAt, minutesUntilLimit: minutesUntilLimit)
    }

    /// Greedily drops points whose rate of change from the last *accepted*
    /// point exceeds `maxPlausibleRatePerSecond`. Comparing against the last
    /// accepted point (not the raw previous point) prevents one bad reading
    /// from also poisoning the comparison for the point right after it (e.g.
    /// a phantom 0% dip followed by a real recovery value).
    private static func filterOutliers(_ points: [UsageDataPoint]) -> [UsageDataPoint] {
        guard let first = points.first else { return points }
        var accepted = [first]
        for point in points.dropFirst() {
            guard let previous = accepted.last else { continue }
            let elapsed = point.timestamp.timeIntervalSince(previous.timestamp)
            guard elapsed > 0 else { continue }
            let rate = abs(Double(point.usage - previous.usage)) / elapsed
            if rate <= maxPlausibleRatePerSecond {
                accepted.append(point)
            } else {
                logger.debug("Discarded outlier point (rate \(rate, privacy: .public) %/s exceeds \(maxPlausibleRatePerSecond, privacy: .public) %/s cap)")
            }
        }
        return accepted
    }
}
