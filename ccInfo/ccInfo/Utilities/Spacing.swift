import Foundation

/// Canonical spacing scale for app UI.
///
/// Use these tokens for all padding/spacing in `Features/**/*.swift`.
/// `ShareableChartView.swift` is exempt — it is export-only artwork on a fixed 440×520 canvas
/// and may use inline pixel values wrapped in its own `ExportTypography` / `ExportSpacing` enum.
///
/// TODO: Move this file into a dedicated `DesignSystem/` folder once the
/// token system grows (e.g. when `Typography` or `Color` tokens join).
enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
}
