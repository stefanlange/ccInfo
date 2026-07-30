import SwiftUI

extension ContextWindow {
    func badgeColor(for model: ModelIdentifier) -> Color {
        switch model.family {
        case .fable:   return .indigo
        case .opus:    return .purple
        case .sonnet:  return .orange
        case .haiku:   return .cyan
        case .unknown: return .secondary
        }
    }
}
