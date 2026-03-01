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

    /// Cached color lookup table (0-100). Rebuilt only when colorScheme changes.
    @State private var colorLookup: [Color] = []

    private var helper: ChartDrawingHelper {
        ChartDrawingHelper(isLightMode: colorScheme == .light)
    }

    private func buildColorLookup() -> [Color] {
        ChartDrawingHelper(isLightMode: colorScheme == .light).buildColorLookup()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { geometry in
                let chartWidth = geometry.size.width - leftMargin
                let colors = colorLookup

                Canvas { context, size in
                    let plotWidth = size.width - leftMargin
                    let plotHeight = chartHeight
                    let points = ChartDrawingHelper.downsample(dataPoints, targetWidth: chartWidth)

                    // Draw dashed threshold lines
                    drawThresholdLines(context: context, width: plotWidth, height: plotHeight)

                    // Draw area fill and line if we have data and colors are ready
                    if points.count > 0, colors.count == 101 {
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
        .onAppear {
            colorLookup = buildColorLookup()
        }
        .onChange(of: colorScheme) { _, _ in
            colorLookup = buildColorLookup()
        }
    }

    private var accessibilityValue: String {
        guard let last = dataPoints.last else { return "No data" }
        return "\(last.usage) percent"
    }

    // MARK: - Position Helpers

    private var windowStart: Date {
        ChartDrawingHelper.windowStart(resetsAt: resetsAt)
    }

    private func xPosition(for timestamp: Date, width: CGFloat) -> CGFloat {
        ChartDrawingHelper.xPosition(for: timestamp, windowStart: windowStart, width: width)
    }

    private func yPosition(for percent: Double, height: CGFloat) -> CGFloat {
        ChartDrawingHelper.yPosition(for: percent, height: height)
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

            if current.isGap || next.isGap || (current.usage == 0 && next.usage == 0) {
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
            let color = helper.colorAt(avgUsage, from: colors)

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

            if current.isGap || next.isGap || (current.usage == 0 && next.usage == 0) {
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
            let color = helper.colorAt(avgUsage, from: colors)

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

        let color = helper.colorAt(Double(last.usage), from: colors)

        var glowPath = Path()
        glowPath.addEllipse(in: CGRect(x: x - 4, y: y - 4, width: 8, height: 8))
        context.fill(glowPath, with: .color(color.opacity(0.4)))

        var dotPath = Path()
        dotPath.addEllipse(in: CGRect(x: x - 2, y: y - 2, width: 4, height: 4))
        context.fill(dotPath, with: .color(color))
    }
}
