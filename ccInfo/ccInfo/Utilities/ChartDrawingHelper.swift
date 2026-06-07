import SwiftUI

/// Shared, stateless helpers for chart color interpolation, geometry, and downsampling.
/// Used by both `UsageChartView` (live menu bar, Canvas) and `ShareableChartView` (image export, Path).
enum ChartDrawingHelper {

    // MARK: - Shared Visual Constants
    // Single source of truth so the live chart and the exported image stay identical.

    /// Opacity of the area fill at the curve, before it fades toward the baseline.
    static let areaFillOpacity: CGFloat = 0.38
    /// Opacity at the center of the current-value glow halo.
    static let glowHaloOpacity: CGFloat = 0.55
    /// Radius (and half the frame) of the soft glow halo.
    static let glowHaloRadius: CGFloat = 8
    /// Diameter of the solid colored core dot.
    static let glowCoreDiameter: CGFloat = 6
    /// Diameter of the white center dot that makes the indicator pop.
    static let glowWhiteCoreDiameter: CGFloat = 3
    /// Upper bound on points fed to the smoother. Dense enough for a faithful shape,
    /// sparse enough that the cubic visibly rounds instead of tracing pixel-quantized steps.
    static let curveSubsampleMax = 40
    /// Vertical breathing room reserved at the top (100%) and bottom (0%) of the plot so the
    /// glow halo of a point at either extreme is never clipped. Equals the glow radius.
    static let plotVerticalInset: CGFloat = glowHaloRadius

    /// Return shape of `horizontalGradientStops`: gradient stops plus the start/end
    /// positions expressed as fractions of the plot width (0...1).
    typealias GradientInfo = (stops: [Gradient.Stop], startFraction: CGFloat, endFraction: CGFloat)

    // MARK: - Color Types

    struct RGBColor {
        let r: Double
        let g: Double
        let b: Double
    }

    // MARK: - Color Lookup

    /// Builds a 0...100 color lookup table for the given appearance.
    static func buildColorLookup(isLightMode: Bool) -> [Color] {
        (0...100).map { colorForUsage(Double($0), isLightMode: isLightMode) }
    }

    /// Returns an indexed color from the lookup table for the given usage percentage.
    static func colorAt(_ percent: Double, from colors: [Color]) -> Color {
        let index = max(0, min(100, Int(percent.rounded())))
        return colors[index]
    }

    // MARK: - Color Interpolation

    /// Computes a smoothly interpolated color for the given usage percentage.
    /// Interpolates across green -> yellow -> orange -> red zones using thresholds from `UtilizationThresholds`.
    static func colorForUsage(_ percent: Double, isLightMode: Bool) -> Color {
        let p = max(0, min(100, percent))

        let deepGreen = RGBColor(r: 0.0, g: 0.65, b: 0.0)
        let green = RGBColor(r: 0.0, g: 0.8, b: 0.0)
        let yellow = RGBColor(r: 1.0, g: 0.9, b: 0.0)
        let orange = RGBColor(r: 1.0, g: 0.6, b: 0.0)
        let red = RGBColor(r: 1.0, g: 0.0, b: 0.0)

        let greenYellow = UtilizationThresholds.greenYellowThreshold
        let yellowOrange = UtilizationThresholds.yellowOrangeThreshold
        let orangeRed = UtilizationThresholds.orangeRedThreshold

        var interpolated: RGBColor

        if p < greenYellow {
            // Smooth gradient from deep green to bright green within the "safe" zone
            let t = p / greenYellow
            interpolated = interpolateRGB(from: deepGreen, to: green, t: t)
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

    private static func interpolateRGB(from: RGBColor, to: RGBColor, t: Double) -> RGBColor {
        RGBColor(
            r: from.r + (to.r - from.r) * t,
            g: from.g + (to.g - from.g) * t,
            b: from.b + (to.b - from.b) * t
        )
    }

    private static func desaturate(_ color: RGBColor, by amount: Double) -> RGBColor {
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

    /// Y position for a usage percentage. Maps 0...100% into the usable band
    /// `[plotVerticalInset, height - plotVerticalInset]`, leaving room for the glow halo at the
    /// extremes so it is never clipped. 100% maps to the top inset, 0% to the bottom inset.
    static func yPosition(for percent: Double, height: CGFloat) -> CGFloat {
        let usable = max(0, height - 2 * plotVerticalInset)
        let normalized = max(0, min(1, percent / 100.0))
        return plotVerticalInset + (1 - CGFloat(normalized)) * usable
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

    // MARK: - Smoothed Path Building (shared by live + export)

    /// Smoothed area + line paths for a dataset, plus `topY` (the smallest y / highest value
    /// across all area paths, used to anchor the fill fade). Runs are split at gaps and at flat
    /// zero spans. Area and line are produced in a single pass over the data.
    struct SmoothedPaths {
        let area: [Path]
        let line: [Path]
        /// Smallest y reached by the curve (the highest data point), or `height` when empty.
        let topY: CGFloat
    }

    static func buildSmoothedPaths(
        points: [UsageDataPoint], windowStart: Date, width: CGFloat, height: CGFloat
    ) -> SmoothedPaths {
        var area: [Path] = []
        var line: [Path] = []
        let baseline = yPosition(for: 0, height: height)
        var topY = baseline
        guard points.count > 1 else { return SmoothedPaths(area: area, line: line, topY: topY) }

        var i = 0
        while i < points.count - 1 {
            let current = points[i]
            let next = points[i + 1]
            if current.isGap || next.isGap || (current.usage == 0 && next.usage == 0) {
                i += 1
                continue
            }

            // Collect a continuous run of non-gap points as plot-space coordinates.
            var run: [CGPoint] = [
                CGPoint(x: xPosition(for: current.timestamp, windowStart: windowStart, width: width),
                        y: yPosition(for: Double(current.usage), height: height)),
                CGPoint(x: xPosition(for: next.timestamp, windowStart: windowStart, width: width),
                        y: yPosition(for: Double(next.usage), height: height))
            ]
            i += 1
            while i < points.count - 1 {
                let cur = points[i]
                let nxt = points[i + 1]
                if cur.isGap || nxt.isGap || (cur.usage == 0 && nxt.usage == 0) { break }
                run.append(CGPoint(
                    x: xPosition(for: nxt.timestamp, windowStart: windowStart, width: width),
                    y: yPosition(for: Double(nxt.usage), height: height)))
                i += 1
            }

            // Thin dense, pixel-quantized runs so the cubic can visibly smooth them.
            let curve = subsampleForCurve(run, maxPoints: curveSubsampleMax)
            guard let first = curve.first, let last = curve.last else { continue }
            for p in curve { topY = min(topY, p.y) }

            // Compute the cubic once, then emit both the open line and the closed area path.
            let segments = monotoneSegments(curve)

            var linePath = Path()
            linePath.move(to: first)
            for s in segments { linePath.addCurve(to: s.to, control1: s.c1, control2: s.c2) }
            line.append(linePath)

            var areaPath = Path()
            areaPath.move(to: CGPoint(x: first.x, y: baseline))
            areaPath.addLine(to: first)
            for s in segments { areaPath.addCurve(to: s.to, control1: s.c1, control2: s.c2) }
            areaPath.addLine(to: CGPoint(x: last.x, y: baseline))
            areaPath.closeSubpath()
            area.append(areaPath)
        }
        return SmoothedPaths(area: area, line: line, topY: topY)
    }

    /// Monotone-cubic (Fritsch–Carlson) Bézier segments through `pts` (ascending x).
    /// Returns one `(to, control1, control2)` per interval; the caller positions the path at `pts[0]`.
    private static func monotoneSegments(
        _ pts: [CGPoint]
    ) -> [(to: CGPoint, c1: CGPoint, c2: CGPoint)] {
        let n = pts.count
        guard n >= 2 else { return [] }

        var intervals = [CGFloat](repeating: 0, count: n - 1)   // x widths between points
        var slopes = [CGFloat](repeating: 0, count: n - 1)      // secant slopes
        for i in 0..<(n - 1) {
            intervals[i] = pts[i + 1].x - pts[i].x
            slopes[i] = intervals[i] == 0 ? 0 : (pts[i + 1].y - pts[i].y) / intervals[i]
        }

        var tangents = [CGFloat](repeating: 0, count: n)
        tangents[0] = slopes[0]
        tangents[n - 1] = slopes[n - 2]
        for i in 1..<(n - 1) {
            tangents[i] = (slopes[i - 1] * slopes[i] <= 0) ? 0 : (slopes[i - 1] + slopes[i]) / 2
        }

        // Fritsch–Carlson monotonicity clamp. Read the original tangents (snapshot) so a value
        // already rescaled by interval i is not re-read when processing interval i+1.
        let original = tangents
        let monotonicityRadius: CGFloat = 3
        for i in 0..<(n - 1) {
            if slopes[i] == 0 {
                tangents[i] = 0
                tangents[i + 1] = 0
            } else {
                let a = original[i] / slopes[i]
                let b = original[i + 1] / slopes[i]
                let magnitudeSquared = a * a + b * b
                // Outside the monotonicity disk of radius 3 → project back onto it.
                if magnitudeSquared > monotonicityRadius * monotonicityRadius {
                    let scale = monotonicityRadius / sqrt(magnitudeSquared)
                    tangents[i] = scale * a * slopes[i]
                    tangents[i + 1] = scale * b * slopes[i]
                }
            }
        }

        var segments: [(to: CGPoint, c1: CGPoint, c2: CGPoint)] = []
        segments.reserveCapacity(n - 1)
        for i in 0..<(n - 1) {
            let p0 = pts[i], p1 = pts[i + 1]
            let c1 = CGPoint(x: p0.x + intervals[i] / 3, y: p0.y + tangents[i] * intervals[i] / 3)
            let c2 = CGPoint(x: p1.x - intervals[i] / 3, y: p1.y - tangents[i + 1] * intervals[i] / 3)
            segments.append((to: p1, c1: c1, c2: c2))
        }
        return segments
    }

    /// Evenly thins a dense run to at most `maxPoints` (keeping first and last).
    private static func subsampleForCurve(_ pts: [CGPoint], maxPoints: Int) -> [CGPoint] {
        guard pts.count > maxPoints, maxPoints >= 2 else { return pts }
        let step = Double(pts.count - 1) / Double(maxPoints - 1)
        var result: [CGPoint] = []
        result.reserveCapacity(maxPoints)
        for i in 0..<maxPoints {
            result.append(pts[Int((Double(i) * step).rounded())])
        }
        return result
    }

    // MARK: - Gradient Stops (shared by live + export)

    /// Builds horizontal gradient stops, mapping each non-gap point's X position to its usage color.
    /// Single pass over the points (no intermediate filtered array, x computed once per point).
    static func horizontalGradientStops(
        points: [UsageDataPoint], windowStart: Date, width: CGFloat, colors: [Color]
    ) -> GradientInfo {
        var minX: CGFloat = width
        var maxX: CGFloat = 0
        var samples: [(x: CGFloat, index: Int)] = []
        samples.reserveCapacity(points.count)
        for point in points where !point.isGap {
            let x = xPosition(for: point.timestamp, windowStart: windowStart, width: width)
            minX = min(minX, x)
            maxX = max(maxX, x)
            samples.append((x: x, index: max(0, min(100, point.usage))))
        }

        let range = maxX - minX
        guard range > 0, width > 0 else {
            let index = samples.first?.index ?? 0
            return ([Gradient.Stop(color: colors[index], location: 0.5)], 0, 1)
        }

        var stops = samples.map {
            Gradient.Stop(color: colors[$0.index], location: ($0.x - minX) / range)
        }
        stops.sort { $0.location < $1.location }

        // Drop near-coincident stops (Gradient requires distinct, ascending locations).
        var deduped: [Gradient.Stop] = []
        for stop in stops {
            if let last = deduped.last, abs(last.location - stop.location) < 1e-4 { continue }
            deduped.append(stop)
        }
        return (deduped, minX / width, maxX / width)
    }
}
