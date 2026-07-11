//
//  WalletMetadata.swift
//  LMPlayground
//
//  Captures the raw FinanceKit transaction fields so we can ship them
//  to Lunch Money's `custom_metadata` field. Stored on the SwiftData
//  Transaction as a JSON string at fetch time, then decoded back to a
//  struct at sync time so the API payload stays well-typed.
//

import Foundation
#if os(iOS)
import FinanceKit
#endif

struct WalletMetadata: Codable {
    let source: String
    let sourceVersion: String?
    var wallet: WalletPayload

    private enum CodingKeys: String, CodingKey {
        case source
        case sourceVersion = "source_version"
        case wallet
    }

    struct WalletPayload: Codable {
        let transactionId: String
        let accountId: String
        // The fields below are filled in at fetch time when available, and
        // patched in by `prepPrefetchedTransactions` for the prefetch flow,
        // hence `var`.
        var accountDisplayName: String?
        var institutionName: String?
        let transactionDate: String           // ISO-8601
        let postedDate: String?               // ISO-8601
        let status: String                    // booked | pending | authorized | memo | rejected
        // Mirrors Transaction.isPending (status != booked). Optional so JSON
        // captured before this field existed still decodes; kept in step by
        // Transaction.refreshMetadataPendingFlag() when the flag flips.
        var isPending: Bool?
        let transactionType: String           // pointOfSale | refund | …
        let creditDebitIndicator: String      // credit | debit
        let transactionDescription: String
        let originalTransactionDescription: String?
        let merchantName: String?
        let merchantCategoryCode: String?
        var merchantCategoryDescription: String?
        let amount: Money
        let foreignAmount: Money?
        let foreignExchangeRate: String?

        private enum CodingKeys: String, CodingKey {
            case transactionId = "transaction_id"
            case accountId = "account_id"
            case accountDisplayName = "account_display_name"
            case institutionName = "institution_name"
            case transactionDate = "transaction_date"
            case postedDate = "posted_date"
            case status
            case isPending = "is_pending"
            case transactionType = "transaction_type"
            case creditDebitIndicator = "credit_debit_indicator"
            case transactionDescription = "transaction_description"
            case originalTransactionDescription = "original_transaction_description"
            case merchantName = "merchant_name"
            case merchantCategoryCode = "merchant_category_code"
            case merchantCategoryDescription = "merchant_category_description"
            case amount
            case foreignAmount = "foreign_amount"
            case foreignExchangeRate = "foreign_exchange_rate"
        }
    }

    struct Money: Codable {
        let value: String   // stringified Decimal to dodge JSON float rounding
        let currency: String
    }
}

// MARK: - JSON helpers

extension WalletMetadata {
    fileprivate static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    fileprivate static let appVersion: String? = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }()

    /// Returns a copy with the patchable fields filled in. Used by the
    /// prefetched-transactions flow where account info and the MCC
    /// description aren't known until later.
    func enriched(
        accountDisplayName: String? = nil,
        institutionName: String? = nil,
        merchantCategoryDescription: String? = nil
    ) -> WalletMetadata {
        var copy = self
        if let v = accountDisplayName { copy.wallet.accountDisplayName = v }
        if let v = institutionName { copy.wallet.institutionName = v }
        if let v = merchantCategoryDescription { copy.wallet.merchantCategoryDescription = v }
        return copy
    }

    /// JSON-encode for storage on the SwiftData Transaction.
    func toJSONString() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Decode from the SwiftData-stored JSON string.
    static func from(jsonString: String?) -> WalletMetadata? {
        guard let jsonString, let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(WalletMetadata.self, from: data)
    }
}

// MARK: - FinanceKit conversion (iOS-only)

#if os(iOS)
extension WalletMetadata {
    /// Build a metadata blob from a raw FinanceKit transaction. Account and
    /// MCC-description fields may be nil when the caller doesn't yet know
    /// them (e.g. `getRecentTransactions`); they can be patched later via
    /// `enriched(...)` from the prefetch flow.
    init(
        from txn: FinanceKit.Transaction,
        accountDisplayName: String? = nil,
        institutionName: String? = nil,
        merchantCategoryDescription: String? = nil
    ) {
        let mccString = txn.merchantCategoryCode.map { String(describing: $0) }

        let amount = Money(
            value: NSDecimalNumber(decimal: txn.transactionAmount.amount).stringValue,
            currency: txn.transactionAmount.currencyCode
        )

        let foreignAmount = txn.foreignCurrencyAmount.map {
            Money(
                value: NSDecimalNumber(decimal: $0.amount).stringValue,
                currency: $0.currencyCode
            )
        }

        // foreignCurrencyExchangeRate is iOS 18+. Gate so we still compile
        // for the BackgroundHandler target if its min version diverges.
        let foreignRateString: String? = {
            if #available(iOS 18, *) {
                return txn.foreignCurrencyExchangeRate.map {
                    NSDecimalNumber(decimal: $0).stringValue
                }
            }
            return nil
        }()

        let payload = WalletPayload(
            transactionId: txn.id.uuidString,
            accountId: txn.accountID.uuidString,
            accountDisplayName: accountDisplayName,
            institutionName: institutionName,
            transactionDate: Self.isoFormatter.string(from: txn.transactionDate),
            postedDate: txn.postedDate.map { Self.isoFormatter.string(from: $0) },
            status: String(describing: txn.status),
            isPending: txn.status == .booked ? false : true,
            transactionType: String(describing: txn.transactionType),
            creditDebitIndicator: String(describing: txn.creditDebitIndicator),
            transactionDescription: txn.transactionDescription,
            originalTransactionDescription: txn.originalTransactionDescription,
            merchantName: txn.merchantName,
            merchantCategoryCode: mccString,
            merchantCategoryDescription: merchantCategoryDescription,
            amount: amount,
            foreignAmount: foreignAmount,
            foreignExchangeRate: foreignRateString
        )

        self.init(source: "lunchsync", sourceVersion: Self.appVersion, wallet: payload)
    }
}
#endif
