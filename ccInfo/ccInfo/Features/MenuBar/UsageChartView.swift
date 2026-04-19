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
    private let leftMargin: CGFloat = 36
    private let bottomMargin: CGFloat = 12

    /// Cached color lookup table (0-100). Rebuilt only when colorScheme changes.
    @State private var colorLookup: [Color] = []

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
                        let (gradient, gradStartX, gradEndX) = horizontalGradientStops(points: points, width: plotWidth, colors: colors)
                        drawAreaFill(context: context, points: points, width: plotWidth, height: plotHeight, gradient: gradient, startX: gradStartX, endX: gradEndX)
                        drawLine(context: context, points: points, width: plotWidth, height: plotHeight, gradient: gradient, startX: gradStartX, endX: gradEndX)
                        drawGlowIndicator(context: context, points: points, width: plotWidth, height: plotHeight, colors: colors)
                    }
                }
                .frame(width: geometry.size.width, height: chartHeight)
                .offset(x: leftMargin, y: 0)

                // Y-axis labels (left of chart)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(verbatim: "100%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(verbatim: "50%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(verbatim: "0%")
                        .font(.caption2)
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
                            .font(.caption2)
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
        guard let last = dataPoints.last else { return String(localized: "No data") }
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

    /// Builds horizontal gradient stops from data points, mapping each point's X position to its usage color.
    private func horizontalGradientStops(
        points: [UsageDataPoint], width: CGFloat, colors: [Color], opacity: Double = 1.0
    ) -> (gradient: Gradient, startX: CGFloat, endX: CGFloat) {
        var stops: [Gradient.Stop] = []
        var minX: CGFloat = width
        var maxX: CGFloat = 0

        for point in points where !point.isGap {
            let x = xPosition(for: point.timestamp, width: width)
            minX = min(minX, x)
            maxX = max(maxX, x)
        }

        let range = maxX - minX
        guard range > 0 else {
            let color = colors[max(0, min(100, points.first(where: { !$0.isGap })?.usage ?? 0))]
            return (Gradient(colors: [color.opacity(opacity)]), minX, maxX)
        }

        for point in points where !point.isGap {
            let x = xPosition(for: point.timestamp, width: width)
            let location = (x - minX) / range
            let index = max(0, min(100, point.usage))
            stops.append(Gradient.Stop(color: colors[index].opacity(opacity), location: location))
        }

        stops.sort { $0.location < $1.location }
        // Deduplicate stops at the same location (required by Gradient)
        var deduped: [Gradient.Stop] = []
        for stop in stops {
            if let last = deduped.last, last.location == stop.location { continue }
            deduped.append(stop)
        }
        return (Gradient(stops: deduped), minX, maxX)
    }

    private func drawAreaFill(context: GraphicsContext, points: [UsageDataPoint], width: CGFloat, height: CGFloat, gradient: Gradient, startX: CGFloat, endX: CGFloat) {
        guard points.count > 1 else { return }
        let areaGradient = Gradient(stops: gradient.stops.map { Gradient.Stop(color: $0.color.opacity(0.25), location: $0.location) })

        // Build continuous paths, splitting at gaps
        var i = 0
        while i < points.count - 1 {
            let current = points[i]
            let next = points[i + 1]
            if current.isGap || next.isGap || (current.usage == 0 && next.usage == 0) {
                i += 1
                continue
            }

            var path = Path()
            let sx = xPosition(for: current.timestamp, width: width)
            let sy = yPosition(for: Double(current.usage), height: height)
            path.move(to: CGPoint(x: sx, y: height))
            path.addLine(to: CGPoint(x: sx, y: sy))

            var lastX = xPosition(for: next.timestamp, width: width)
            var lastY = yPosition(for: Double(next.usage), height: height)
            path.addLine(to: CGPoint(x: lastX, y: lastY))
            i += 1

            while i < points.count - 1 {
                let cur = points[i]
                let nxt = points[i + 1]
                if cur.isGap || nxt.isGap || (cur.usage == 0 && nxt.usage == 0) { break }
                lastX = xPosition(for: nxt.timestamp, width: width)
                lastY = yPosition(for: Double(nxt.usage), height: height)
                path.addLine(to: CGPoint(x: lastX, y: lastY))
                i += 1
            }

            path.addLine(to: CGPoint(x: lastX, y: height))
            path.closeSubpath()

            context.fill(path, with: .linearGradient(
                areaGradient,
                startPoint: CGPoint(x: startX, y: 0),
                endPoint: CGPoint(x: endX, y: 0)
            ))
        }
    }

    private func drawLine(context: GraphicsContext, points: [UsageDataPoint], width: CGFloat, height: CGFloat, gradient: Gradient, startX: CGFloat, endX: CGFloat) {
        guard points.count > 1 else { return }

        var i = 0
        while i < points.count - 1 {
            let current = points[i]
            let next = points[i + 1]
            if current.isGap || next.isGap || (current.usage == 0 && next.usage == 0) {
                i += 1
                continue
            }

            var path = Path()
            let sx = xPosition(for: current.timestamp, width: width)
            let sy = yPosition(for: Double(current.usage), height: height)
            path.move(to: CGPoint(x: sx, y: sy))

            var lastX = xPosition(for: next.timestamp, width: width)
            var lastY = yPosition(for: Double(next.usage), height: height)
            path.addLine(to: CGPoint(x: lastX, y: lastY))
            i += 1

            while i < points.count - 1 {
                let cur = points[i]
                let nxt = points[i + 1]
                if cur.isGap || nxt.isGap || (cur.usage == 0 && nxt.usage == 0) { break }
                lastX = xPosition(for: nxt.timestamp, width: width)
                lastY = yPosition(for: Double(nxt.usage), height: height)
                path.addLine(to: CGPoint(x: lastX, y: lastY))
                i += 1
            }

            context.stroke(path, with: .linearGradient(
                gradient,
                startPoint: CGPoint(x: startX, y: 0),
                endPoint: CGPoint(x: endX, y: 0)
            ), lineWidth: 1.5)
        }
    }

    private func drawGlowIndicator(context: GraphicsContext, points: [UsageDataPoint], width: CGFloat, height: CGFloat, colors: [Color]) {
        guard points.count >= 2 else { return }
        guard let last = points.last, !last.isGap else { return }
        // No glow when there's no real usage in the window
        guard points.contains(where: { !$0.isGap && $0.usage > 0 }) else { return }

        let x = xPosition(for: last.timestamp, width: width)
        let y = yPosition(for: Double(last.usage), height: height)

        let helper = ChartDrawingHelper(isLightMode: colorScheme == .light)
        let color = helper.colorAt(Double(last.usage), from: colors)

        var glowPath = Path()
        glowPath.addEllipse(in: CGRect(x: x - 4, y: y - 4, width: 8, height: 8))
        context.fill(glowPath, with: .color(color.opacity(0.4)))

        var dotPath = Path()
        dotPath.addEllipse(in: CGRect(x: x - 2, y: y - 2, width: 4, height: 4))
        context.fill(dotPath, with: .color(color))
    }
}
