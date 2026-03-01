import SwiftUI

@MainActor
enum ChartShareService {
    /// Renders the shareable chart view as an NSImage.
    static func renderChartImage(
        dataPoints: [UsageDataPoint],
        utilization: Double,
        resetsAt: Date?,
        resetTimeFormatted: String?
    ) -> NSImage? {
        let view = ShareableChartView(
            dataPoints: dataPoints,
            utilization: utilization,
            resetsAt: resetsAt,
            resetTimeFormatted: resetTimeFormatted
        )

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2.0 // Retina quality
        return renderer.nsImage
    }

    /// Presents the macOS share sheet with the rendered chart image.
    /// Writes the image to a temporary PNG file so the share picker shows a thumbnail preview.
    static func presentShareSheet(
        dataPoints: [UsageDataPoint],
        utilization: Double,
        resetsAt: Date?,
        resetTimeFormatted: String?,
        from sourceView: NSView
    ) {
        guard let image = renderChartImage(
            dataPoints: dataPoints,
            utilization: utilization,
            resetsAt: resetsAt,
            resetTimeFormatted: resetTimeFormatted
        ) else { return }

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CCInfo-Chart-\(Int(utilization))pct", conformingTo: .png)

        do {
            try pngData.write(to: tempURL)
        } catch {
            return
        }

        let picker = NSSharingServicePicker(items: [tempURL])
        picker.show(relativeTo: sourceView.bounds, of: sourceView, preferredEdge: .minY)
    }
}
