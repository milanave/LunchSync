//
//  CurrencyFormatter.swift
//  LMPlayground
//
//  Created by Bob Sanders on 10/31/24.
//
import Foundation
import SwiftUI

struct CurrencyFormatter {
    static let shared = CurrencyFormatter()
    private let numberFormatter: NumberFormatter
    
    init() {
        numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        numberFormatter.minimumFractionDigits = 2
        numberFormatter.maximumFractionDigits = 2
        numberFormatter.groupingSeparator = ","
        numberFormatter.groupingSize = 3
    }
    
    /// Formats a Double as currency with commas and 2 decimal places
    /// - Parameters:
    ///   - amount: The amount to format
    ///   - includeCurrencySymbol: Whether to include the $ symbol
    /// - Returns: Formatted string (e.g. "$1,234.56" or "1,234.56")
    func format(_ amount: Double, includeCurrencySymbol: Bool = true) -> String {
        let formattedNumber = numberFormatter.string(from: NSNumber(value: abs(amount))) ?? "0.00"
        let prefix = amount < 0 ? "-" : ""
        let currencySymbol = includeCurrencySymbol ? "$" : ""
        return "\(prefix)\(currencySymbol)\(formattedNumber)"
    }
    
    /// Formats a Double as currency with color based on positive/negative value
    /// - Parameter amount: The amount to format
    /// - Returns: A Text view with appropriate color and formatting
    func formattedText(_ amount: Double) -> Text {
        Text(format(amount))
            .foregroundColor(amount < 0 ? .red : .primary)
    }
}

/// Global function that formats a Double as currency string like $1,234,123.00
/// - Parameter amount: The amount to format
/// - Returns: Formatted currency string with commas and two decimal places
func niceAmount(_ amount: Double) -> String {
    return CurrencyFormatter.shared.format(amount)
}
