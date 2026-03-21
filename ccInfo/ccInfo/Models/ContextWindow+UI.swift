import SwiftUI

extension ContextWindow {
    func badgeColor(for model: ModelIdentifier) -> Color {
        switch model.family {
        case .opus:    return .purple
        case .sonnet:  return isExtendedContext ? .red : .orange
        case .haiku:   return .cyan
        case .unknown: return .secondary
        }
    }
}
