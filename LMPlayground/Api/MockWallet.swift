//
//  MockAppleWallet.swift
//  LMPlayground
//
//  Created by Bob Sanders on 12/7/24.
import SwiftUI
import SwiftData
import FinanceKit
import Combine

class MockWallet: Wallet {
    @Published var transactions: [Transaction] = []
    let context: ModelContext
    var apiToken: String
    
    override required init(context: ModelContext, apiToken: String) {
        self.context = context
        self.apiToken = apiToken
        super.init(context: context, apiToken: apiToken)
        // Add some mock transactions
        self.transactions = [
            Transaction(id: UUID().uuidString, account: "Mock Account", payee: "Mock Store", amount: 42.0, date: Date(), lm_id: "", lm_account: "", sync: .pending),
            Transaction(id: UUID().uuidString, account: "Mock Account", payee: "Mock Shop", amount: 24.0, date: Date(), lm_id: "", lm_account: "", sync: .complete)
        ]
    }
    
    override func getTransactionsWithStatus(_ status: Transaction.SyncStatus) -> [Transaction] {
        return transactions.filter { $0.sync == status }
    }
    
    override func getTransactionsWithStatus(_ statuses: [Transaction.SyncStatus]) -> [Transaction] {
        return transactions.filter { statuses.contains($0.sync) }
    }
    
    override func getSyncedAccounts() -> [Account] {
        return [
            Account(id: "1", name: "Mock Account 1", balance: 1000, lm_id: "", lm_name: ""),
            Account(id: "2", name: "Mock Account 2", balance: 2000, lm_id: "", lm_name: "")
        ]
    }
    
    override func addLog(message: String, level: Int) {}
    
    override func replaceTransaction(newTrans: Transaction) {
        if let index = transactions.firstIndex(where: { $0.id == newTrans.id }) {
            transactions[index] = newTrans
        } else {
            transactions.append(newTrans)
        }
    }
    
    override func getAPIAccountName() async throws -> String {
        return "Account Holder"
    }
    
    override func syncTransactions(progressCallback: @escaping (Wallet.SyncProgress) -> Void) async throws {
        // Simulate sync progress
        progressCallback(Wallet.SyncProgress(current: 5, total: 10, status: "Syncing..."))
    }
    
    override func syncAccountBalances(accounts: [Account]) async throws {}
    
    override func addNotification(time: Double, title: String, subtitle: String, body: String) async {}
}
