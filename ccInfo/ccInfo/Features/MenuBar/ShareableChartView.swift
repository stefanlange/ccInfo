import SwiftUI

/// Path-based chart view optimized for image export via `ImageRenderer`.
/// Unlike `UsageChartView` (which uses Canvas), this view draws all chart
/// elements as SwiftUI `Path` views so they render correctly in a static image.
struct ShareableChartView: View {
    let dataPoints: [UsageDataPoint]
    let utilization: Double
    let resetsAt: Date?
    let resetTimeFormatted: String?

    // MARK: - Layout Constants

    private let totalWidth: CGFloat = 440
    private let totalHeight: CGFloat = 520
    private let leftMargin: CGFloat = 32
    private let chartHeight: CGFloat = 320
    private let lineWidth: CGFloat = 2.5

    private let helper: ChartDrawingHelper
    private let colorLookup: [Color]

    private var windowStart: Date {
        ChartDrawingHelper.windowStart(resetsAt: resetsAt)
    }

    init(dataPoints: [UsageDataPoint], utilization: Double, resetsAt: Date?, resetTimeFormatted: String?) {
        self.dataPoints = dataPoints
        self.utilization = utilization
        self.resetsAt = resetsAt
        self.resetTimeFormatted = resetTimeFormatted
        let h = ChartDrawingHelper(isLightMode: false)
        self.helper = h
        self.colorLookup = h.buildColorLookup()
    }

    // MARK: - Colors

    private let bgDark = Color(red: 0.08, green: 0.08, blue: 0.12)
    private let bgCard = Color(red: 0.12, green: 0.12, blue: 0.17)
    private let textPrimary = Color.white
    private let textMuted = Color(white: 0.5)
    private let accent = Color(red: 0.4, green: 0.6, blue: 1.0)

    // MARK: - Body

    var body: some View {
        ZStack {
            // Dark gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.06, blue: 0.14),
                    Color(red: 0.10, green: 0.08, blue: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 0) {
                // Header
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text("\(Int(utilization))")
                        .font(.system(size: 56, weight: .black, design: .rounded))
                        .foregroundStyle(helper.colorForUsage(utilization))
                    Text("%")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(helper.colorForUsage(utilization).opacity(0.6))
                    Spacer()
                    if let resetTimeFormatted {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(localized: "Resets in"))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(textMuted)
                                .textCase(.uppercase)
                                .kerning(1)
                            Text(resetTimeFormatted)
                                .font(.system(size: 20, weight: .bold, design: .monospaced))
                                .foregroundStyle(textPrimary)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 4)

                // Subtitle
                HStack {
                    Text(String(localized: "5-Hour Window"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accent)
                        .textCase(.uppercase)
                        .kerning(1.5)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

                // Chart card
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 0) {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("100%")
                            Spacer()
                            Text("50%")
                            Spacer()
                            Text("0%")
                        }
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(textMuted)
                        .frame(width: leftMargin, height: chartHeight)

                        chartPlot
                            .frame(height: chartHeight)
                            .clipped()
                    }

                    HStack(spacing: 0) {
                        ForEach(0..<6) { hour in
                            if hour > 0 { Spacer() }
                            Text("\(hour)h")
                        }
                    }
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(textMuted)
                    .padding(.leading, leftMargin)
                    .padding(.top, 6)
                }
                .padding(16)
                .background(bgCard)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)

                Spacer()

                // Footer
                HStack {
                    Spacer()
                    Text("ccInfo")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(textMuted.opacity(0.6))
                        .kerning(2)
                        .textCase(.uppercase)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
        .frame(width: totalWidth, height: totalHeight)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Chart Plot

    /// Single GeometryReader that computes downsampled points once and draws all chart layers.
    private var chartPlot: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let colors = colorLookup
            let points = ChartDrawingHelper.downsample(dataPoints, targetWidth: width)
            let winStart = windowStart

            // Threshold lines
            ThresholdLinesShape()
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                .foregroundStyle(Color.secondary.opacity(0.3))

            // Build continuous area and line paths, splitting at gaps
            let areaPaths: [Path] = ShareableChartView.buildContinuousPaths(
                points: points, windowStart: winStart, width: width, height: height, closed: true
            )
            let linePaths: [Path] = ShareableChartView.buildContinuousPaths(
                points: points, windowStart: winStart, width: width, height: height, closed: false
            )

            let hGradient = ShareableChartView.horizontalGradientStops(
                points: points, windowStart: winStart, width: width, colors: colors
            )

            // Area fill with horizontal gradient
            ForEach(0..<areaPaths.count, id: \.self) { idx in
                areaPaths[idx]
                    .fill(LinearGradient(
                        stops: hGradient.stops.map { Gradient.Stop(color: $0.color.opacity(0.25), location: $0.location) },
                        startPoint: UnitPoint(x: hGradient.startFraction, y: 0),
                        endPoint: UnitPoint(x: hGradient.endFraction, y: 0)
                    ))
            }

            // Line with horizontal gradient
            ForEach(0..<linePaths.count, id: \.self) { idx in
                linePaths[idx]
                    .stroke(LinearGradient(
                        stops: hGradient.stops,
                        startPoint: UnitPoint(x: hGradient.startFraction, y: 0),
                        endPoint: UnitPoint(x: hGradient.endFraction, y: 0)
                    ), lineWidth: lineWidth)
            }

            // Glow indicator
            if let last = points.last, !last.isGap, points.contains(where: { !$0.isGap && $0.usage > 0 }) {
                let x = ChartDrawingHelper.xPosition(for: last.timestamp, windowStart: winStart, width: width)
                let y = ChartDrawingHelper.yPosition(for: Double(last.usage), height: height)
                let color = helper.colorAt(Double(last.usage), from: colors)

                Circle()
                    .fill(color.opacity(0.4))
                    .frame(width: 12, height: 12)
                    .position(x: x, y: y)

                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                    .position(x: x, y: y)
            }
        }
    }

    // MARK: - Gradient Helpers

    /// Builds horizontal gradient stops from data points, mapping X position to usage color.
    static func horizontalGradientStops(
        points: [UsageDataPoint], windowStart: Date, width: CGFloat, colors: [Color]
    ) -> (stops: [Gradient.Stop], startFraction: CGFloat, endFraction: CGFloat) {
        var stops: [Gradient.Stop] = []
        var minX: CGFloat = width
        var maxX: CGFloat = 0

        let nonGapPoints = points.filter { !$0.isGap }
        for point in nonGapPoints {
            let x = ChartDrawingHelper.xPosition(for: point.timestamp, windowStart: windowStart, width: width)
            minX = min(minX, x)
            maxX = max(maxX, x)
        }

        let range = maxX - minX
        guard range > 0, width > 0 else {
            let color = colors[max(0, min(100, points.first(where: { !$0.isGap })?.usage ?? 0))]
            return ([Gradient.Stop(color: color, location: 0.5)], 0, 1)
        }

        for point in nonGapPoints {
            let x = ChartDrawingHelper.xPosition(for: point.timestamp, windowStart: windowStart, width: width)
            let location = (x - minX) / range
            let index = max(0, min(100, point.usage))
            stops.append(Gradient.Stop(color: colors[index], location: location))
        }

        stops.sort { $0.location < $1.location }
        // Deduplicate
        var deduped: [Gradient.Stop] = []
        for stop in stops {
            if let last = deduped.last, last.location == stop.location { continue }
            deduped.append(stop)
        }

        return (deduped, minX / width, maxX / width)
    }

    /// Builds continuous paths from data points, splitting at gaps.
    /// When `closed` is true, creates closed area paths (with baseline at bottom).
    /// When `closed` is false, creates open line paths.
    static func buildContinuousPaths(
        points: [UsageDataPoint], windowStart: Date, width: CGFloat, height: CGFloat, closed: Bool
    ) -> [Path] {
        guard points.count > 1 else { return [] }

        var paths: [Path] = []
        var i = 0
        while i < points.count - 1 {
            let current = points[i]
            let next = points[i + 1]
            if current.isGap || next.isGap || (current.usage == 0 && next.usage == 0) {
                i += 1
                continue
            }

            var path = Path()
            let startX = ChartDrawingHelper.xPosition(for: current.timestamp, windowStart: windowStart, width: width)
            let startY = ChartDrawingHelper.yPosition(for: Double(current.usage), height: height)

            if closed {
                path.move(to: CGPoint(x: startX, y: height))
                path.addLine(to: CGPoint(x: startX, y: startY))
            } else {
                path.move(to: CGPoint(x: startX, y: startY))
            }

            var lastX = ChartDrawingHelper.xPosition(for: next.timestamp, windowStart: windowStart, width: width)
            var lastY = ChartDrawingHelper.yPosition(for: Double(next.usage), height: height)
            path.addLine(to: CGPoint(x: lastX, y: lastY))
            i += 1

            while i < points.count - 1 {
                let cur = points[i]
                let nxt = points[i + 1]
                if cur.isGap || nxt.isGap || (cur.usage == 0 && nxt.usage == 0) {
                    break
                }
                lastX = ChartDrawingHelper.xPosition(for: nxt.timestamp, windowStart: windowStart, width: width)
                lastY = ChartDrawingHelper.yPosition(for: Double(nxt.usage), height: height)
                path.addLine(to: CGPoint(x: lastX, y: lastY))
                i += 1
            }

            if closed {
                path.addLine(to: CGPoint(x: lastX, y: height))
                path.closeSubpath()
            }

            paths.append(path)
        }
        return paths
    }
}

// MARK: - Threshold Lines Shape

/// Draws dashed horizontal lines at 0%, 50%, and 100% positions.
struct ThresholdLinesShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            let thresholds: [Double] = [0, 50, 100]
            for threshold in thresholds {
                let y = rect.height - (CGFloat(threshold / 100.0) * rect.height)
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
        }
    }
}

/// A button that renders and shares the 5-hour chart image via the system share sheet.
/// Uses NSViewRepresentable because NSSharingServicePicker requires an NSView anchor.
struct ShareChartButton: NSViewRepresentable {
    let dataPoints: [UsageDataPoint]
    let utilization: Double
    let resetsAt: Date?
    let resetTimeFormatted: String?

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: String(localized: "Share Chart"))
        button.bezelStyle = .inline
        button.isBordered = false
        button.imageScaling = .scaleProportionallyDown
        button.target = context.coordinator
        button.action = #selector(Coordinator.shareChart(_:))
        button.contentTintColor = .secondaryLabelColor
        // Match small icon size
        button.controlSize = .small
        if let symbolConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular) as NSImage.SymbolConfiguration? {
            button.image = button.image?.withSymbolConfiguration(symbolConfig)
        }
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.dataPoints = dataPoints
        context.coordinator.utilization = utilization
        context.coordinator.resetsAt = resetsAt
        context.coordinator.resetTimeFormatted = resetTimeFormatted
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            dataPoints: dataPoints,
            utilization: utilization,
            resetsAt: resetsAt,
            resetTimeFormatted: resetTimeFormatted
        )
    }

    @MainActor
    class Coordinator: NSObject {
        var dataPoints: [UsageDataPoint]
        var utilization: Double
        var resetsAt: Date?
        var resetTimeFormatted: String?

        init(dataPoints: [UsageDataPoint], utilization: Double, resetsAt: Date?, resetTimeFormatted: String?) {
            self.dataPoints = dataPoints
            self.utilization = utilization
            self.resetsAt = resetsAt
            self.resetTimeFormatted = resetTimeFormatted
        }

        @objc func shareChart(_ sender: NSButton) {
            ChartShareService.presentShareSheet(
                dataPoints: dataPoints,
                utilization: utilization,
                resetsAt: resetsAt,
                resetTimeFormatted: resetTimeFormatted,
                from: sender
            )
        }
    }
}
