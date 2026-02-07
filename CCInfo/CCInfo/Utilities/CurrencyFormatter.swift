import Foundation

extension Double {
    /// Formats as USD currency with adaptive decimal precision:
    /// - 2 decimals for amounts >= $0.01 (e.g. "$1.23")
    /// - 4 decimals for amounts < $0.01 and > 0 (e.g. "$0.0045")
    /// - "$0.00" for exact zero
    func formattedCurrency() -> String {
        let precision = (self > 0 && self < 0.01) ? 4 : 2
        return "$" + String(format: "%.\(precision)f", self)
    }
}
