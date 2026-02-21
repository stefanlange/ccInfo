import SwiftUI

/// Canvas-based area chart that visualizes the 5-hour usage timeline.
/// Uses smooth color interpolation across usage zones and displays axes, threshold lines, and a glowing indicator.
struct UsageChartView: View {
    let dataPoints: [UsageDataPoint]
    /// When the 5h window resets. Used to position data points relative to the window lifecycle.
    let resetsAt: Date?

    @Environment(\.colorScheme) private var colorScheme

    // Chart dimensions
    private let chartHeight: CGFloat = 50
    private let leftMargin: CGFloat = 30
    private let bottomMargin: CGFloat = 12

    // Color zone thresholds
    private var greenYellowThreshold: Double { UtilizationThresholds.greenYellowThreshold }
    private var yellowOrangeThreshold: Double { UtilizationThresholds.yellowOrangeThreshold }
    private var orangeRedThreshold: Double { UtilizationThresholds.orangeRedThreshold }

    /// Pre-computed color lookup table (0-100), rebuilt when colorScheme changes.
    private var colorLookup: [Color] {
        (0...100).map { colorForUsageRaw(Double($0)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { geometry in
                let chartWidth = geometry.size.width - leftMargin
                let colors = colorLookup

                Canvas { context, size in
                    let plotWidth = size.width - leftMargin
                    let plotHeight = chartHeight
                    let points = downsample(dataPoints, targetWidth: chartWidth)

                    // Draw dashed threshold lines
                    drawThresholdLines(context: context, width: plotWidth, height: plotHeight)

                    // Draw area fill and line if we have data
                    if points.count > 0 {
                        drawAreaFill(context: context, points: points, width: plotWidth, height: plotHeight, colors: colors)
                        drawLine(context: context, points: points, width: plotWidth, height: plotHeight, colors: colors)
                        drawGlowIndicator(context: context, points: points, width: plotWidth, height: plotHeight, colors: colors)
                    }
                }
                .frame(width: geometry.size.width, height: chartHeight)
                .offset(x: leftMargin, y: 0)

                // Y-axis labels (left of chart)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("100%")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("50%")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("0%")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
                .frame(width: leftMargin - 6, height: chartHeight, alignment: .trailing)
            }
            .frame(height: chartHeight)

            // X-axis labels (below chart)
            HStack(spacing: 0) {
                Spacer()
                    .frame(width: leftMargin)
                HStack(spacing: 0) {
                    ForEach(0..<6) { hour in
                        if hour > 0 { Spacer() }
                        Text("\(hour)h")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: bottomMargin)
            .offset(y: 2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel("5-Hour Window usage chart")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        guard let last = dataPoints.last else { return "No data" }
        return "\(last.usage) percent"
    }

    // MARK: - Color Interpolation

    /// Returns an indexed color from the lookup table for the given usage percentage.
    private func colorAt(_ percent: Double, from colors: [Color]) -> Color {
        let index = max(0, min(100, Int(percent.rounded())))
        return colors[index]
    }

    /// Computes a smoothly interpolated color for the given usage percentage (used to build lookup table).
    private func colorForUsageRaw(_ percent: Double) -> Color {
        let p = max(0, min(100, percent))

        let green = RGBColor(r: 0.0, g: 0.8, b: 0.0)
        let yellow = RGBColor(r: 1.0, g: 0.9, b: 0.0)
        let orange = RGBColor(r: 1.0, g: 0.6, b: 0.0)
        let red = RGBColor(r: 1.0, g: 0.0, b: 0.0)

        var interpolated: RGBColor

        if p < greenYellowThreshold {
            interpolated = green
        } else if p < yellowOrangeThreshold {
            let t = (p - greenYellowThreshold) / (yellowOrangeThreshold - greenYellowThreshold)
            interpolated = interpolateRGB(from: green, to: yellow, t: t)
        } else if p < orangeRedThreshold {
            let t = (p - yellowOrangeThreshold) / (orangeRedThreshold - yellowOrangeThreshold)
            interpolated = interpolateRGB(from: yellow, to: orange, t: t)
        } else {
            let t = (p - orangeRedThreshold) / (100 - orangeRedThreshold)
            interpolated = interpolateRGB(from: orange, to: red, t: t)
        }

        if colorScheme == .dark {
            interpolated = desaturate(interpolated, by: 0.15)
        }

        return Color(red: interpolated.r, green: interpolated.g, blue: interpolated.b)
    }

    private struct RGBColor {
        let r: Double
        let g: Double
        let b: Double
    }

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

    // MARK: - Drawing

    private func drawThresholdLines(context: GraphicsContext, width: CGFloat, height: CGFloat) {
        let thresholds: [Double] = [0, 50, 100]
        let dashPattern: [CGFloat] = [4, 3]

        for threshold in thresholds {
            let y = height - (CGFloat(threshold / 100.0) * height)
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: width, y: y))

            // Fix #2: stroke() does not mutate context — no copy needed
            context.stroke(
                path,
                with: .color(Color.secondary.opacity(0.3)),
                style: StrokeStyle(lineWidth: 1, dash: dashPattern)
            )
        }
    }

    private func drawAreaFill(context: GraphicsContext, points: [UsageDataPoint], width: CGFloat, height: CGFloat, colors: [Color]) {
        guard points.count > 1 else { return }

        var i = 0
        while i < points.count - 1 {
            let current = points[i]
            let next = points[i + 1]

            if current.isGap || next.isGap {
                i += 1
                continue
            }

            let currentX = xPosition(for: current.timestamp, width: width)
            let nextX = xPosition(for: next.timestamp, width: width)
            let currentY = yPosition(for: Double(current.usage), height: height)
            let nextY = yPosition(for: Double(next.usage), height: height)

            var path = Path()
            path.move(to: CGPoint(x: currentX, y: height))
            path.addLine(to: CGPoint(x: currentX, y: currentY))
            path.addLine(to: CGPoint(x: nextX, y: nextY))
            path.addLine(to: CGPoint(x: nextX, y: height))
            path.closeSubpath()

            let avgUsage = Double(current.usage + next.usage) / 2.0
            let color = colorAt(avgUsage, from: colors)

            context.fill(path, with: .color(color.opacity(0.25)))

            i += 1
        }
    }

    private func drawLine(context: GraphicsContext, points: [UsageDataPoint], width: CGFloat, height: CGFloat, colors: [Color]) {
        guard points.count > 1 else { return }

        var i = 0
        while i < points.count - 1 {
            let current = points[i]
            let next = points[i + 1]

            if current.isGap || next.isGap {
                i += 1
                continue
            }

            let currentX = xPosition(for: current.timestamp, width: width)
            let nextX = xPosition(for: next.timestamp, width: width)
            let currentY = yPosition(for: Double(current.usage), height: height)
            let nextY = yPosition(for: Double(next.usage), height: height)

            var path = Path()
            path.move(to: CGPoint(x: currentX, y: currentY))
            path.addLine(to: CGPoint(x: nextX, y: nextY))

            let avgUsage = Double(current.usage + next.usage) / 2.0
            let color = colorAt(avgUsage, from: colors)

            context.stroke(path, with: .color(color), lineWidth: 1.5)

            i += 1
        }
    }

    private func drawGlowIndicator(context: GraphicsContext, points: [UsageDataPoint], width: CGFloat, height: CGFloat, colors: [Color]) {
        guard points.count >= 2 else { return }
        guard let last = points.last, !last.isGap else { return }
        // No glow when there's no real usage in the window
        guard points.contains(where: { !$0.isGap && $0.usage > 0 }) else { return }

        let x = xPosition(for: last.timestamp, width: width)
        let y = yPosition(for: Double(last.usage), height: height)

        let color = colorAt(Double(last.usage), from: colors)

        var glowPath = Path()
        glowPath.addEllipse(in: CGRect(x: x - 4, y: y - 4, width: 8, height: 8))
        context.fill(glowPath, with: .color(color.opacity(0.4)))

        var dotPath = Path()
        dotPath.addEllipse(in: CGRect(x: x - 2, y: y - 2, width: 4, height: 4))
        context.fill(dotPath, with: .color(color))
    }

    // MARK: - Position Helpers

    private var windowStart: Date {
        if let resetsAt {
            return resetsAt.addingTimeInterval(-5 * 3600)
        }
        return Date().addingTimeInterval(-5 * 3600)
    }

    private var windowEnd: Date {
        resetsAt ?? Date()
    }

    private func xPosition(for timestamp: Date, width: CGFloat) -> CGFloat {
        let elapsed = timestamp.timeIntervalSince(windowStart)
        let normalized = elapsed / (5 * 3600)
        return CGFloat(max(0, min(1, normalized))) * width
    }

    private func yPosition(for percent: Double, height: CGFloat) -> CGFloat {
        let normalized = percent / 100.0
        return height - (CGFloat(normalized) * height)
    }

    // MARK: - Downsampling

    /// Downsamples data points to match chart pixel width, keeping max usage per bucket to preserve peaks.
    private func downsample(_ points: [UsageDataPoint], targetWidth: CGFloat) -> [UsageDataPoint] {
        let pixelWidth = Int(targetWidth)
        guard points.count > pixelWidth else { return points }

        let bucketSize = Double(points.count) / Double(pixelWidth)
        var downsampled: [UsageDataPoint] = []
        downsampled.reserveCapacity(pixelWidth)

        for i in 0..<pixelWidth {
            let startIdx = Int(Double(i) * bucketSize)
            let endIdx = min(Int(Double(i + 1) * bucketSize), points.count)

            guard startIdx < endIdx else { continue }

            // Fix #3: Use slice directly instead of copying to Array
            if let maxPoint = points[startIdx..<endIdx].max(by: { $0.usage < $1.usage }) {
                downsampled.append(maxPoint)
            }
        }

        return downsampled
    }
}
