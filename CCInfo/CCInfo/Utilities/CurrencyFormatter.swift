import Foundation

extension Double {
    /// Formats as currency with adaptive decimal precision:
    /// - 2 decimals for amounts >= $0.01 (e.g. "$1.23")
    /// - 4 decimals for amounts < $0.01 and > 0 (e.g. "$0.0045")
    /// - "$0.00" for exact zero
    /// Locale-aware: uses system locale for decimal separator and currency symbol.
    func formattedCurrency(locale: Locale = .current) -> String {
        let precision = (self > 0 && self < 0.01) ? 4 : 2
        return self.formatted(
            .currency(code: locale.currency?.identifier ?? "USD")
            .precision(.fractionLength(precision))
            .locale(locale)
        )
    }
}
