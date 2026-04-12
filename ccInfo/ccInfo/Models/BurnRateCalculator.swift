import Foundation

enum BurnRateCalculator {
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

        // Guard: need at least 3 data points
        guard recentPoints.count >= 3 else { return nil }

        // Linear regression: find slope in usage-percent per second
        // Use the earliest point as the reference time to avoid floating-point precision issues
        let referenceTime = recentPoints.first!.timestamp
        let pairs: [(x: Double, y: Double)] = recentPoints.map { point in
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
}
