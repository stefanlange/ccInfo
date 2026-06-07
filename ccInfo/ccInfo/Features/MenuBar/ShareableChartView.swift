import SwiftUI

/// Fixed-size typography for the 440×520 export canvas.
/// Do not reuse in app UI — `Features/**/*.swift` uses semantic SwiftUI fonts
/// and `Spacing` tokens (see `Utilities/Spacing.swift`).
private enum ExportTypography {
    static let heroNumber: CGFloat = 56        // main percent hero
    static let headline: CGFloat = 28          // secondary headline
    static let sectionLabel: CGFloat = 20      // section value labels (monospaced)
    static let subheadlineBold: CGFloat = 12   // bold subheadlines
    static let caption: CGFloat = 10           // metadata captions
    static let microMonospaced: CGFloat = 9    // mono axis/value micro-labels
}

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

    private let colorLookup: [Color]

    private var windowStart: Date {
        ChartDrawingHelper.windowStart(resetsAt: resetsAt)
    }

    init(dataPoints: [UsageDataPoint], utilization: Double, resetsAt: Date?, resetTimeFormatted: String?) {
        self.dataPoints = dataPoints
        self.utilization = utilization
        self.resetsAt = resetsAt
        self.resetTimeFormatted = resetTimeFormatted
        // Export image is always dark — build the dark-appearance lookup once.
        self.colorLookup = ChartDrawingHelper.buildColorLookup(isLightMode: false)
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
                        .font(.system(size: ExportTypography.heroNumber, weight: .black, design: .rounded))
                        .foregroundStyle(ChartDrawingHelper.colorForUsage(utilization, isLightMode: false))
                    Text("%")
                        .font(.system(size: ExportTypography.headline, weight: .bold, design: .rounded))
                        .foregroundStyle(ChartDrawingHelper.colorForUsage(utilization, isLightMode: false).opacity(0.6))
                    Spacer()
                    if let resetTimeFormatted {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(localized: "Resets in"))
                                .font(.system(size: ExportTypography.caption, weight: .semibold))
                                .foregroundStyle(textMuted)
                                .textCase(.uppercase)
                                .kerning(1)
                            Text(resetTimeFormatted)
                                .font(.system(size: ExportTypography.sectionLabel, weight: .bold, design: .monospaced))
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
                        .font(.system(size: ExportTypography.subheadlineBold, weight: .semibold))
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
                        ZStack(alignment: .trailing) {
                            ForEach([100.0, 50.0, 0.0], id: \.self) { threshold in
                                Text("\(Int(threshold))%")
                                    .offset(y: ChartDrawingHelper.yPosition(for: threshold, height: chartHeight) - chartHeight / 2)
                            }
                        }
                        .font(.system(size: ExportTypography.microMonospaced, weight: .medium, design: .monospaced))
                        .foregroundStyle(textMuted)
                        .padding(.trailing, 6)
                        .frame(width: leftMargin, height: chartHeight, alignment: .trailing)

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
                    .font(.system(size: ExportTypography.microMonospaced, weight: .medium, design: .monospaced))
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
                        .font(.system(size: ExportTypography.caption, weight: .bold))
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

    private var chartPlot: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let colors = colorLookup
            let points = ChartDrawingHelper.downsample(dataPoints, targetWidth: width)
            let winStart = windowStart

            ThresholdLinesShape()
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                .foregroundStyle(Color.secondary.opacity(0.3))

            let smoothed = ChartDrawingHelper.buildSmoothedPaths(
                points: points, windowStart: winStart, width: width, height: height)
            let grad = ChartDrawingHelper.horizontalGradientStops(
                points: points, windowStart: winStart, width: width, colors: colors)

            // Area fill: horizontal hue gradient, faded from the curve down to the baseline.
            // NOTE: UsageChartView mirrors this fade with Canvas drawLayer + `.destinationIn`.
            // Shared constants (ChartDrawingHelper.areaFillOpacity) and the curve-anchored topY
            // keep the two implementations visually identical.
            let areaStops = grad.stops.map {
                Gradient.Stop(color: $0.color.opacity(ChartDrawingHelper.areaFillOpacity), location: $0.location)
            }
            let fillTopFraction = smoothed.topY / max(height, 1)
            let fillBottomFraction = (height - ChartDrawingHelper.plotVerticalInset) / max(height, 1)
            ZStack {
                ForEach(0..<smoothed.area.count, id: \.self) { idx in
                    smoothed.area[idx].fill(LinearGradient(
                        stops: areaStops,
                        startPoint: UnitPoint(x: grad.startFraction, y: 0),
                        endPoint: UnitPoint(x: grad.endFraction, y: 0)))
                }
            }
            .mask(
                LinearGradient(colors: [.white, .clear],
                               startPoint: UnitPoint(x: 0.5, y: fillTopFraction),
                               endPoint: UnitPoint(x: 0.5, y: fillBottomFraction))
            )

            // Line: horizontal hue gradient.
            ForEach(0..<smoothed.line.count, id: \.self) { idx in
                smoothed.line[idx].stroke(LinearGradient(
                    stops: grad.stops,
                    startPoint: UnitPoint(x: grad.startFraction, y: 0),
                    endPoint: UnitPoint(x: grad.endFraction, y: 0)
                ), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }

            // Glow indicator: soft radial halo + white center. Guard count >= 2 so a single
            // point (which produces no line/area) doesn't leave an orphaned dot.
            if points.count >= 2, let last = points.last, !last.isGap,
               points.contains(where: { !$0.isGap && $0.usage > 0 }) {
                let x = ChartDrawingHelper.xPosition(for: last.timestamp, windowStart: winStart, width: width)
                let y = ChartDrawingHelper.yPosition(for: Double(last.usage), height: height)
                let color = ChartDrawingHelper.colorAt(Double(last.usage), from: colors)
                let halo = ChartDrawingHelper.glowHaloRadius

                Circle()
                    .fill(RadialGradient(
                        gradient: Gradient(colors: [color.opacity(ChartDrawingHelper.glowHaloOpacity), color.opacity(0.0)]),
                        center: .center, startRadius: 0, endRadius: halo))
                    .frame(width: halo * 2, height: halo * 2)
                    .position(x: x, y: y)
                Circle().fill(color)
                    .frame(width: ChartDrawingHelper.glowCoreDiameter, height: ChartDrawingHelper.glowCoreDiameter)
                    .position(x: x, y: y)
                Circle().fill(Color.white)
                    .frame(width: ChartDrawingHelper.glowWhiteCoreDiameter, height: ChartDrawingHelper.glowWhiteCoreDiameter)
                    .position(x: x, y: y)
            }
        }
    }
}

// MARK: - Threshold Lines Shape

/// Draws dashed horizontal lines at 0%, 50%, and 100% positions.
struct ThresholdLinesShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            let thresholds: [Double] = [0, 50, 100]
            for threshold in thresholds {
                let y = ChartDrawingHelper.yPosition(for: threshold, height: rect.height)
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
