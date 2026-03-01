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
    /// Includes a "Copy" option via a custom sharing service since NSSharingServicePicker
    /// does not include clipboard copying by default.
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

        let delegate = SharePickerDelegate(image: image)
        // Keep delegate alive until picker dismisses
        sharePickerDelegate = delegate

        let picker = NSSharingServicePicker(items: [tempURL])
        picker.delegate = delegate
        picker.show(relativeTo: sourceView.bounds, of: sourceView, preferredEdge: .minY)
    }

    /// Retained reference so the delegate stays alive while the picker is shown.
    private static var sharePickerDelegate: SharePickerDelegate?
}

// MARK: - Share Picker Delegate

/// Injects a "Copy" clipboard service into the sharing service picker.
@MainActor
private final class SharePickerDelegate: NSObject, NSSharingServicePickerDelegate {
    private let image: NSImage

    init(image: NSImage) {
        self.image = image
    }

    func sharingServicePicker(
        _ sharingServicePicker: NSSharingServicePicker,
        sharingServicesForItems items: [Any],
        proposedSharingServices proposedServices: [NSSharingService]
    ) -> [NSSharingService] {
        let copyService = NSSharingService(
            title: String(localized: "Copy to Clipboard"),
            image: NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: String(localized: "Copy to Clipboard"))!,
            alternateImage: nil
        ) { [image] in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([image])
        }
        return [copyService] + proposedServices
    }
}
