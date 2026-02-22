import SwiftUI

enum UtilizationThresholds {
    static let greenYellowThreshold: Double = 50
    static let yellowOrangeThreshold: Double = 75
    static let orangeRedThreshold: Double = 90

    static func color(for utilization: Double) -> Color {
        Color(nsColor: nsColor(for: utilization))
    }

    static func nsColor(for utilization: Double) -> NSColor {
        switch utilization {
        case ..<greenYellowThreshold:  return .systemGreen
        case ..<yellowOrangeThreshold: return .systemYellow
        case ..<orangeRedThreshold:    return .systemOrange
        default:                       return .systemRed
        }
    }
}

struct ColoredBarProgressStyle: ProgressViewStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.primary.opacity(0.12))
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: geo.size.width * (configuration.fractionCompleted ?? 0))
            }
        }
        .frame(height: 6)
    }
}
