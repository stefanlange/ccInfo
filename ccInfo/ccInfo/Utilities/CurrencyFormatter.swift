import Foundation

extension Double {
    /// Formats as USD currency with two decimal places (e.g. "$1.23", "$0.00").
    /// Sub-cent amounts round to "$0.00" rather than gaining extra digits.
    func formattedCurrency() -> String {
        "$" + String(format: "%.2f", self)
    }
}
