import SwiftUI

/// Canvas-based area chart that visualizes the 5-hour usage timeline.
/// Uses smooth color interpolation across usage zones and displays axes, threshold lines, and a glowing indicator.
struct UsageChartView: View {
    let dataPoints: [UsageDataPoint]
    /// When the 5h window resets. Used to position data points relative to the window lifecycle.
    let resetsAt: Date?

    @Environment(\.colorScheme) private var colorScheme

    // Chart dimensions
    private let chartHeight: CGFloat = 110
    private let lineWidth: CGFloat = 2.0
    private let leftMargin: CGFloat = 36
    private let bottomMargin: CGFloat = 12

    /// Cached color lookup table (0-100). Rebuilt only when colorScheme changes.
    @State private var colorLookup: [Color] = []

    private func buildColorLookup() -> [Color] {
        ChartDrawingHelper.buildColorLookup(isLightMode: colorScheme == .light)
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

                    drawThresholdLines(context: context, width: plotWidth, height: plotHeight)

                    if points.count > 0, colors.count == 101 {
                        let grad = ChartDrawingHelper.horizontalGradientStops(
                            points: points, windowStart: windowStart, width: plotWidth, colors: colors)
                        let smoothed = ChartDrawingHelper.buildSmoothedPaths(
                            points: points, windowStart: windowStart, width: plotWidth, height: plotHeight)
                        let hasRealData = points.contains { !$0.isGap && $0.usage > 0 }
                        drawAreaFill(context: context, areaPaths: smoothed.area, width: plotWidth, height: plotHeight, topY: smoothed.topY, grad: grad)
                        drawLine(context: context, linePaths: smoothed.line, width: plotWidth, grad: grad)
                        drawGlowIndicator(context: context, points: points, width: plotWidth, height: plotHeight, colors: colors, hasRealData: hasRealData)
                    }
                }
                .frame(width: geometry.size.width, height: chartHeight)
                .offset(x: leftMargin, y: 0)

                // Y-axis labels (left of chart), each vertically centered on its gridline.
                ZStack(alignment: .trailing) {
                    ForEach([100.0, 50.0, 0.0], id: \.self) { threshold in
                        Text(verbatim: "\(Int(threshold))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .offset(y: ChartDrawingHelper.yPosition(for: threshold, height: chartHeight) - chartHeight / 2)
                    }
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
            let y = ChartDrawingHelper.yPosition(for: threshold, height: height)
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

    /// Fills the area under the curve with the horizontal hue gradient, faded out toward the baseline.
    private func drawAreaFill(context: GraphicsContext, areaPaths: [Path], width: CGFloat, height: CGFloat, topY: CGFloat, grad: ChartDrawingHelper.GradientInfo) {
        guard !areaPaths.isEmpty else { return }
        // NOTE: ShareableChartView mirrors this fade with a SwiftUI `.mask`.
        // Shared constants (ChartDrawingHelper.areaFillOpacity) and the curve-anchored `topY`
        // keep the two implementations visually identical.
        let clipShape = areaPaths.reduce(into: Path()) { $0.addPath($1) }
        let plotRect = CGRect(x: 0, y: 0, width: width, height: height)
        let baseline = height - ChartDrawingHelper.plotVerticalInset

        context.drawLayer { layer in
            layer.clip(to: clipShape)
            // 1) Horizontal hue gradient across the whole plot.
            layer.fill(Path(plotRect), with: .linearGradient(
                Gradient(stops: grad.stops),
                startPoint: CGPoint(x: grad.startFraction * width, y: 0),
                endPoint: CGPoint(x: grad.endFraction * width, y: 0)))
            // 2) Multiply alpha by a fade from the curve (topY) down to the baseline (F2 look).
            layer.blendMode = .destinationIn
            layer.fill(Path(plotRect), with: .linearGradient(
                Gradient(stops: [
                    .init(color: .white.opacity(ChartDrawingHelper.areaFillOpacity), location: 0),
                    .init(color: .white.opacity(0.0), location: 1)
                ]),
                startPoint: CGPoint(x: 0, y: topY),
                endPoint: CGPoint(x: 0, y: baseline)))
        }
    }

    /// Strokes the smoothed line with the horizontal hue gradient.
    private func drawLine(context: GraphicsContext, linePaths: [Path], width: CGFloat, grad: ChartDrawingHelper.GradientInfo) {
        for path in linePaths {
            context.stroke(path, with: .linearGradient(
                Gradient(stops: grad.stops),
                startPoint: CGPoint(x: grad.startFraction * width, y: 0),
                endPoint: CGPoint(x: grad.endFraction * width, y: 0)),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
    }

    private func drawGlowIndicator(context: GraphicsContext, points: [UsageDataPoint], width: CGFloat, height: CGFloat, colors: [Color], hasRealData: Bool) {
        guard points.count >= 2, hasRealData else { return }
        guard let last = points.last, !last.isGap else { return }

        let x = xPosition(for: last.timestamp, width: width)
        let y = yPosition(for: Double(last.usage), height: height)
        let color = ChartDrawingHelper.colorAt(Double(last.usage), from: colors)

        let halo = ChartDrawingHelper.glowHaloRadius
        let core = ChartDrawingHelper.glowCoreDiameter
        let white = ChartDrawingHelper.glowWhiteCoreDiameter

        // Soft radial halo
        context.fill(
            Path(ellipseIn: CGRect(x: x - halo, y: y - halo, width: halo * 2, height: halo * 2)),
            with: .radialGradient(
                Gradient(colors: [color.opacity(ChartDrawingHelper.glowHaloOpacity), color.opacity(0.0)]),
                center: CGPoint(x: x, y: y), startRadius: 0, endRadius: halo))
        // Colored core
        context.fill(Path(ellipseIn: CGRect(x: x - core / 2, y: y - core / 2, width: core, height: core)), with: .color(color))
        // White center for pop
        context.fill(Path(ellipseIn: CGRect(x: x - white / 2, y: y - white / 2, width: white, height: white)), with: .color(.white))
    }
}
