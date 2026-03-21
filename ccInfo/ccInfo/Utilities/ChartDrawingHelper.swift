import SwiftUI

/// Shared helper for chart color interpolation, position calculations, and downsampling.
/// Used by both `UsageChartView` (live menu bar) and `ShareableChartView` (image export).
struct ChartDrawingHelper {
    let isLightMode: Bool

    // MARK: - Color Types

    struct RGBColor {
        let r: Double
        let g: Double
        let b: Double
    }

    // MARK: - Color Lookup

    /// Builds a 0...100 color lookup table for the current appearance.
    func buildColorLookup() -> [Color] {
        (0...100).map { colorForUsage(Double($0)) }
    }

    /// Returns an indexed color from the lookup table for the given usage percentage.
    func colorAt(_ percent: Double, from colors: [Color]) -> Color {
        let index = max(0, min(100, Int(percent.rounded())))
        return colors[index]
    }

    // MARK: - Color Interpolation

    /// Computes a smoothly interpolated color for the given usage percentage.
    /// Interpolates across green -> yellow -> orange -> red zones using thresholds from `UtilizationThresholds`.
    func colorForUsage(_ percent: Double) -> Color {
        let p = max(0, min(100, percent))

        let green = RGBColor(r: 0.0, g: 0.8, b: 0.0)
        let yellow = RGBColor(r: 1.0, g: 0.9, b: 0.0)
        let orange = RGBColor(r: 1.0, g: 0.6, b: 0.0)
        let red = RGBColor(r: 1.0, g: 0.0, b: 0.0)

        let greenYellow = UtilizationThresholds.greenYellowThreshold
        let yellowOrange = UtilizationThresholds.yellowOrangeThreshold
        let orangeRed = UtilizationThresholds.orangeRedThreshold

        var interpolated: RGBColor

        if p < greenYellow {
            interpolated = green
        } else if p < yellowOrange {
            let t = (p - greenYellow) / (yellowOrange - greenYellow)
            interpolated = interpolateRGB(from: green, to: yellow, t: t)
        } else if p < orangeRed {
            let t = (p - yellowOrange) / (orangeRed - yellowOrange)
            interpolated = interpolateRGB(from: yellow, to: orange, t: t)
        } else {
            let t = (p - orangeRed) / (100 - orangeRed)
            interpolated = interpolateRGB(from: orange, to: red, t: t)
        }

        if !isLightMode {
            interpolated = desaturate(interpolated, by: 0.15)
        }

        return Color(red: interpolated.r, green: interpolated.g, blue: interpolated.b)
    }

    // MARK: - Private Color Helpers

    private func interpolateRGB(from: RGBColor, to: RGBColor, t: Double) -> RGBColor {
        RGBColor(
            r: from.r + (to.r - from.r) * t,
            g: from.g + (to.g - from.g) * t,
            b: from.b + (to.b - from.b) * t
        )
    }

    private func desaturate(_ color: RGBColor, by amount: Double) -> RGBColor {
        let gray = 0.299 * color.r + 0.587 * color.g + 0.114 * color.b
        return RGBColor(
            r: color.r + (gray - color.r) * amount,
            g: color.g + (gray - color.g) * amount,
            b: color.b + (gray - color.b) * amount
        )
    }

    // MARK: - Position Helpers

    /// X position for a timestamp within the 5-hour window.
    static func xPosition(for timestamp: Date, windowStart: Date, width: CGFloat) -> CGFloat {
        let elapsed = timestamp.timeIntervalSince(windowStart)
        let normalized = elapsed / (5 * 3600)
        return CGFloat(max(0, min(1, normalized))) * width
    }

    /// Y position for a usage percentage within the chart height.
    static func yPosition(for percent: Double, height: CGFloat) -> CGFloat {
        let normalized = percent / 100.0
        return height - (CGFloat(normalized) * height)
    }

    /// Computes the window start date from the reset time (5 hours before reset).
    static func windowStart(resetsAt: Date?) -> Date {
        if let resetsAt {
            return resetsAt.addingTimeInterval(-5 * 3600)
        }
        return Date().addingTimeInterval(-5 * 3600)
    }

    // MARK: - Downsampling

    /// Downsamples data points to match chart pixel width, keeping max usage per bucket to preserve peaks.
    static func downsample(_ points: [UsageDataPoint], targetWidth: CGFloat) -> [UsageDataPoint] {
        let pixelWidth = Int(targetWidth)
        guard points.count > pixelWidth else { return points }

        let bucketSize = Double(points.count) / Double(pixelWidth)
        var downsampled: [UsageDataPoint] = []
        downsampled.reserveCapacity(pixelWidth)

        for i in 0..<pixelWidth {
            let startIdx = Int(Double(i) * bucketSize)
            let endIdx = min(Int(Double(i + 1) * bucketSize), points.count)

            guard startIdx < endIdx else { continue }

            if let maxPoint = points[startIdx..<endIdx].max(by: { $0.usage < $1.usage }) {
                downsampled.append(maxPoint)
            }
        }

        return downsampled
    }
}
