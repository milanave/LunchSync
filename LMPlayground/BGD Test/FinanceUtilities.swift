/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
The functions for fetching finance store data.
*/

import FinanceKit
import Foundation

struct FinanceUtilities {
    
    // MARK: - Weekly Spending Total
    
    static func calculateWeeklySpendingTotal() async throws -> Decimal {
        // Fetch all of the accounts you're tracking.
        let accounts = try await FinanceStore.shared.accounts(query: AccountQuery())
        
        var total: Decimal = 0
        
        for account in accounts {
            total += try await calculateTotal(for: account)
        }
        
        // Spending is a negative value, so you need to invert it to get a positive total.
        return -total
    }
    
    static func calculateTotal(for account: FinanceKit.Account) async throws -> Decimal {
        let startOfWeek = Date.startOfWeek
        
        // Fetch only the past week's worth of transactions for the account.
        let transactionQuery = TransactionQuery(
            predicate: #Predicate {
                $0.accountID == account.id && $0.transactionDate > startOfWeek
            }
        )
        
        // Run the query.
        let transactions = try await FinanceStore.shared.transactions(query: transactionQuery)
        
        // Filter out nonspending transactions.
        let filteredTransactions = getSpendingTransactions(for: transactions)
        
        // Total the transaction values based on the account type.
        if account.assetAccount != nil {
            return totalForAssetTransactions(filteredTransactions)
        } else if account.liabilityAccount != nil {
            return totalForLiabilityTransactions(filteredTransactions)
        } else {
            return 0
        }
    }
    
    static func getSpendingTransactions(for transactions: [FinanceKit.Transaction]) -> [FinanceKit.Transaction] {
        let allowedTypes: [TransactionType] = [.check, .pointOfSale, .unknown]
        
        return transactions.filter {
            allowedTypes.contains($0.transactionType)
        }
    }
    
    // If there's an asset account, credit transactions increase the value, and debits decrease it.
    static func totalForAssetTransactions(_ transactions: [FinanceKit.Transaction]) -> Decimal {
        transactions.reduce(0) { partialResult, transaction in
            let amount = transaction.transactionAmount.amount
            
            switch transaction.creditDebitIndicator {
            case .credit:
                return partialResult + amount
            case .debit:
                return partialResult - amount
            default:
                return 0
            }
        }
    }
    
    // If there's a liability account, credit transactions decrease the value, and debits increase it.
    static func totalForLiabilityTransactions(_ transactions: [FinanceKit.Transaction]) -> Decimal {
        transactions.reduce(0) { partialResult, transaction in
            let amount = transaction.transactionAmount.amount
            
            switch transaction.creditDebitIndicator {
            case .credit:
                return partialResult - amount
            case .debit:
                return partialResult + amount
            default:
                return 0
            }
        }
    }
    
    // MARK: - Transaction Fetching
    
    static func fetchLastWeekOfTransactions() async throws -> [FinanceKit.Transaction] {
        let startOfWeek = Date.startOfWeek
        
        // Fetch transactions since the start of the week and show them in chronological order.
        return try await FinanceStore.shared.transactions(
            query: TransactionQuery(
                sortDescriptors: [.init(\.transactionDate, order: .reverse)],
                predicate: #Predicate {
                    $0.transactionDate > startOfWeek
                }
            )
        )
    }
}

extension Date {
    static var startOfWeek: Date {
        let calendar = Calendar(identifier: .iso8601)
        guard let date = calendar.dateComponents(
            [.calendar, .yearForWeekOfYear, .weekOfYear],
            from: Date()
        ).date else {
            fatalError("Couldn't create date")
        }
        return date
    }
}
